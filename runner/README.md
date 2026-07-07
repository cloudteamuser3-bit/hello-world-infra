# Runner VM

One GCE VM (`e2-small`, `me-west1-a`) running **three separate GitHub
Actions runner registrations** - one per repo (`hello-world-app`,
`hello-world-infra`, `hello-world-environments`), each its own directory
and its own systemd service. This is the standard way to serve multiple
repos from one machine without a GitHub organization (which is what
org-level runners would require instead).

Why one VM instead of three: you're solo, cost matters, and this is a test
case - three tiny idle runner processes on one cheap VM costs a fraction of
three separate VMs. See `../ARCHITECTURE.md` for the fuller reasoning and
the org-level upgrade path if a teammate ever joins.

## One-time setup

### 1. Create a fine-grained GitHub PAT for runner registration

This is **separate** from the GitHub App used elsewhere in the system (that
one has `Contents: Read & write` for committing files and opening PRs).
This PAT needs a different permission - **Administration: Read and
write** - on all three repos, because minting a runner registration token
requires repo-admin-level access:

1. GitHub → Settings → Developer settings → Personal access tokens →
   Fine-grained tokens → Generate new token
2. Repository access: select `hello-world-app`, `hello-world-infra`,
   `hello-world-environments`
3. Permissions: **Administration — Read and write**
4. Set an expiration and put a reminder to rotate it

### 2. Create the Terraform state bucket (if not already done)

```bash
gsutil mb -l me-west1 gs://mafat-ai-gee-monitor-dev-tfstate
gsutil versioning set on gs://mafat-ai-gee-monitor-dev-tfstate
```

### 3. Apply

```bash
cd runner
terraform init
terraform apply
```

### 4. Add the PAT to Secret Manager

```bash
echo -n "github_pat_..." | gcloud secrets versions add github-actions-runner-pat \
  --project=mafat-ai-gee-monitor-dev \
  --data-file=-
```

### 5. Reboot to trigger registration

```bash
gcloud compute instances reset gh-actions-runner-01 --zone=me-west1-a
```

### 6. Confirm all three registered

Check each repo's **Settings → Actions → Runners** — you should see
`gcp-runner-<hostname>-<repo-name>` listed as idle, once per repo.

## Notes

- **Concurrency is actually better than a single shared runner**: because
  each repo has its own runner process, a job in the app repo and a job in
  the infra repo can run at the same time instead of queuing behind each
  other.
- **The VM's attached service account has the union of permissions** all
  three repos' pipelines need (Artifact Registry write, Storage admin,
  Cloud Run admin, IAM service account admin/user, logging) — see
  `main.tf`'s `google_project_iam_member.runner_roles`. This is broader
  than any single repo strictly needs on its own, which is the real
  tradeoff of sharing one machine across repos — worth revisiting if this
  ever stops being a test case.
- **If you outgrow this**: creating a free GitHub organization and moving
  to one org-level runner registration collapses all three service
  installs into one — a same-day change, not a redesign.
