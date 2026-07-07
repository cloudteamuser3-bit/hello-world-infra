#!/usr/bin/env bash
# Writes the outcome of an apply attempt to two places:
#   1. This repo's own .state/<env>.json (infra repo's private bookkeeping
#      of "what digest is actually live" - used by check_for_changes.sh)
#   2. The environments repo's status/<env>.json (the signal the
#      environments repo's own push-triggered workflow reacts to)
#
# Both are plain git operations - clone/commit/push. No dispatch API.
#
# Usage: report_status.sh <env> <result:success|failure> <image_tag> <image_digest> <run_url>
# Requires: VCS_TOKEN, VCS_ORG, ENVIRONMENTS_REPO (for step 2)
set -euo pipefail

ENV="${1:?}"
RESULT="${2:?}"
IMAGE_TAG="${3:?}"
IMAGE_DIGEST="${4:?}"
RUN_URL="${5:?}"

APPLIED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# --- 1. Update local state, only on success (failure shouldn't move the
#        "last known good" pointer) ---
if [ "$RESULT" = "success" ]; then
  cat > ".state/${ENV}.json" <<EOF
{
  "environment": "${ENV}",
  "applied_image_digest": "${IMAGE_DIGEST}"
}
EOF
  git config user.name "infra-bot"
  git config user.email "infra-bot@users.noreply.github.com"
  git add ".state/${ENV}.json"
  git commit -m "Record successful apply of ${IMAGE_TAG} to ${ENV}" || echo "No local state change"
  git push
fi

# --- 2. Write status back to the environments repo ---
: "${VCS_TOKEN:?VCS_TOKEN must be set}"
: "${VCS_ORG:?VCS_ORG must be set}"
: "${ENVIRONMENTS_REPO:?ENVIRONMENTS_REPO must be set}"

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

REPO_URL="https://x-access-token:${VCS_TOKEN}@github.com/${VCS_ORG}/${ENVIRONMENTS_REPO}.git"
git clone --depth 1 --quiet "$REPO_URL" "$WORKDIR"

cat > "$WORKDIR/status/${ENV}.json" <<EOF
{
  "environment": "${ENV}",
  "image_tag": "${IMAGE_TAG}",
  "image_digest": "${IMAGE_DIGEST}",
  "result": "${RESULT}",
  "applied_at": "${APPLIED_AT}",
  "run_url": "${RUN_URL}"
}
EOF

cd "$WORKDIR"
git config user.name "infra-bot"
git config user.email "infra-bot@users.noreply.github.com"
git add "status/${ENV}.json"
if git diff --cached --quiet; then
  echo "No status change to report"
  exit 0
fi
git commit -m "Report ${RESULT}: ${ENV} at ${IMAGE_TAG}"
git push
