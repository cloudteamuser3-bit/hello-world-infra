#!/usr/bin/env bash
# Runs on every boot. Installs Docker + gcloud once (shared by all repos'
# jobs), then registers ONE self-hosted runner service PER REPO - each is
# its own directory, its own systemd service, its own registration. This is
# officially supported by GitHub (multiple runners on one machine just
# need separate folders) and is how a single, cheap VM can serve three
# separate repos without needing a GitHub organization for org-level
# runners.
set -euo pipefail

GITHUB_OWNER="${github_owner}"
REPOS="${repos}"          # space-separated: "hello-world-app hello-world-infra hello-world-environments"
RUNNER_VERSION="${runner_version}"
SECRET_ID="${github_pat_secret_id}"
PROJECT_ID="${project_id}"

# --- Install Docker ---
if ! command -v docker &> /dev/null; then
  apt-get update
  apt-get install -y ca-certificates curl gnupg jq python3-pip python3-venv
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
fi

# --- Install Google Cloud CLI (gcloud, gsutil - needed by infra repo's scripts) ---
if ! command -v gcloud &> /dev/null; then
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
    | tee /etc/apt/sources.list.d/google-cloud-sdk.list
  curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
  apt-get update
  apt-get install -y google-cloud-cli
fi

# --- Install Terraform (needed for infra repo's jobs) ---
if ! command -v terraform &> /dev/null; then
  curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    | tee /etc/apt/sources.list.d/hashicorp.list
  apt-get update
  apt-get install -y terraform
fi

# --- Shared runner user ---
if ! id -u runner &> /dev/null; then
  useradd -m -s /bin/bash runner
  usermod -aG docker runner
fi

GITHUB_PAT=$(gcloud secrets versions access latest --secret="$SECRET_ID" --project="$PROJECT_ID")

# --- Register one runner PER REPO, each in its own directory ---
for REPO in $REPOS; do
  RUNNER_DIR="/home/runner/actions-runner-$${REPO}"
  mkdir -p "$RUNNER_DIR"
  cd "$RUNNER_DIR"

  if [ ! -f ./config.sh ]; then
    curl -fsSL -o actions-runner.tar.gz \
      "https://github.com/actions/runner/releases/download/v$${RUNNER_VERSION}/actions-runner-linux-x64-$${RUNNER_VERSION}.tar.gz"
    tar xzf actions-runner.tar.gz
    rm actions-runner.tar.gz
    chown -R runner:runner "$RUNNER_DIR"
  fi

  REG_TOKEN=$(curl -fsSL -X POST \
    -H "Authorization: Bearer $${GITHUB_PAT}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$${GITHUB_OWNER}/$${REPO}/actions/runners/registration-token" \
    | jq -r .token)

  sudo -u runner ./config.sh \
    --url "https://github.com/$${GITHUB_OWNER}/$${REPO}" \
    --token "$${REG_TOKEN}" \
    --name "gcp-runner-$(hostname)-$${REPO}" \
    --labels "self-hosted,linux,gcp" \
    --work "_work" \
    --unattended \
    --replace

  # Each repo's runner is installed as its own uniquely-named systemd
  # service, since svc.sh derives the service name from the directory/
  # runner name - running it from each separate RUNNER_DIR is what keeps
  # them from colliding.
  ./svc.sh install runner
  ./svc.sh start
done
