# Architecture: Three-Repo CI/CD for `hello-world`

This document explains the full system across all three repos, why it's
shaped this way, and what comes next. Read this first if you're new to the
project — the individual repo READMEs assume you've read this.

## The three repos and their one job each

| Repo | Job | Trusted with |
|---|---|---|
| **hello-world-app** | Build, test, and containerize the application | Artifact Registry push only |
| **hello-world-environments** | Record what image is deployed to each environment; run the promotion workflow | A GitHub App scoped to write only its own `environments/*.yaml` files |
| **hello-world-infra** | All Terraform; the only thing that actually talks to GCP with apply-level power | GCP service account with `storage.admin`, `run.admin`, etc. |

No repo needs to know how another repo works internally. Each only reads or
writes across a narrow, well-defined interface (a YAML file's contents, or
a `repository_dispatch` event's payload).

## The full flow, end to end

```
 1. Dev pushes code to hello-world-app (main)
          │
          ▼
 2. app repo: lint → test → build image → push to Artifact Registry
    (every step above is a script call - see scripts/lint.sh, test.sh,
    build_and_push.sh)
          │
          ▼
 3. app repo's scripts/update_environment.sh clones the environments repo,
    writes environments/dev.yaml, commits, pushes.
    (dev is unattended by design - no review needed to reach dev, and this
    is PLAIN GIT, not a platform dispatch API)
          │
          ▼
 4. infra repo's poll-and-apply.yml runs on a SCHEDULE (every 10 min, or
    manually via workflow_dispatch). scripts/check_for_changes.sh clones
    the environments repo and compares its desired image_digest against
    this repo's own .state/dev.json record of what's actually been applied.
          │
     (changed?)
          │
          ▼
 5. scripts/terraform_apply.sh runs terraform apply (dev) →
    scripts/smoke_test.sh executes the Cloud Run Job and verifies
    hello_world.txt landed in the dev bucket
          │
     ┌────┴────┐
   PASS       FAIL
     │           │
     ▼           ▼
 6a. scripts/    6b. scripts/generate_postmortem.py scaffolds an SRE
 report_status.sh   post-mortem, scripts/open_incident_issue.sh opens it
 writes .state/      as a GitHub issue - process stops here, nothing is
 dev.json AND        promoted. report_status.sh still records "failure"
 status/dev.json     to environments repo's status/dev.json.
 in the
 environments repo
 (plain git commit
 + push, not an API
 call)
     │
     ▼
 7. environments repo's promote-on-status-success.yml is triggered by an
    ORDINARY path-filtered push event (status/dev.json changed) - this
    trigger type is native to virtually every CI platform, nothing
    GitHub-specific here. It reads the status file; if result=success,
    scripts/update_environment_file.sh + build_promotion_report.sh +
    open_promotion_pr.sh open/update a PR bumping staging.yaml
          │
          ▼
 8. A human reviews and merges the PR (fast - it's a one-line version bump
    plus a report that's already done the legwork)
          │
          ▼
 9. Steps 4-8 repeat for staging → prod, with the prod PR additionally
    requiring CODEOWNERS approval (platform/SRE specifically, not just
    any reviewer)
```

Multiple pushes to `main` in the app repo in one day don't create multiple
staging PRs — the promotion workflow updates the same open PR in place
(fixed branch name), so a reviewer sees one PR with the day's full
changelog, not five to click through.

## Thin CI, thick scripts — and why it matters for portability

Every workflow YAML file in this system is deliberately close to empty:
each step is a one- or two-line call into a script in that repo's
`scripts/` directory. The test for whether this worked: **delete every
`.github/workflows/*.yml` file, and a competent engineer should be able to
reconstruct 90% of this system's behavior just by reading `scripts/` and
running things by hand.** That's true here — every script runs standalone,
takes plain arguments/env vars, and has zero knowledge of `$GITHUB_OUTPUT`,
`${{ }}` expressions, or any other GitHub Actions-specific context.

This means migrating to another CI platform (GitLab CI, Jenkins, etc.)
means rewriting the *workflow YAML* — triggers, job graph, secret
injection — but not re-deriving any actual logic. The logic already lives
in portable scripts.

**The two remaining genuine platform-specific seams, both marked
explicitly in the code:**

1. **Minting `VCS_TOKEN`** — currently a GitHub App installation token. On
   GitLab this becomes a Project/Group Access Token pulled from a CI
   variable. Every script downstream only ever sees a plain token string,
   so this is a one-step swap, not a redesign.
2. **`scripts/open_promotion_pr.sh` and `scripts/open_incident_issue.sh`**
   — these wrap `gh pr create` / `gh issue create`. On GitLab, swap for
   `glab mr create` / `glab issue create`. Isolated to exactly these two
   files.

## Why poll-based triggering instead of repository_dispatch

The original design used GitHub's `repository_dispatch` API to have one
repo tell another "something changed, go act." That's fast (near-instant),
but it's a GitHub-specific mechanism with no direct equivalent on other
platforms — porting it means redesigning the cross-repo signal, not just
swapping a CLI command.

The current design replaces it with two portable primitives instead:

- **Plain git commits to shared files** (`environments/*.yaml`,
  `status/*.json`) as the actual cross-repo "message" — any platform can
  clone, write a file, commit, and push.
- **A scheduled poll** (`schedule:` cron) in the infra repo to notice those
  commits, since infra repo can't be pushed to and simply react to
  a push in the environments repo the way the environments repo can react
  to its own file changes.

**The honest tradeoff:** promotion is now bounded by the poll interval
(10 minutes here) instead of being instant. For a small team validating a
test case, that's a reasonable price for removing the single largest
platform-specific dependency in the system.

## Why three repos, not one or two

**Blast radius.** A bad app code push, worst case, ships a broken image —
recoverable by not promoting it. A bad Terraform apply can delete
infrastructure. These deserve different levels of caution and different
credentials, which is much easier to enforce with a hard repo boundary than
with folder conventions inside one repo.

**Least privilege, concretely enforced.** The app repo's pipeline
physically cannot run `terraform apply`, because its runner's credentials
don't include Terraform-relevant IAM roles at all. This isn't a policy
someone has to remember — it's structurally true.

**Deploy state as a first-class, auditable thing.** "What's running in
prod right now" is a question you can answer by opening one file in one
repo and reading its git blame — not by reconstructing it from two
pipelines' logs. Every promotion is a commit; every commit has a PR; every
PR has a paper trail.

**The real cost, honestly stated.** Coordinating a change that spans app
code and infrastructure (e.g., the app needs a new environment variable
that only Terraform can create) requires sequencing two PRs across two
repos by hand — there's no single "monorepo PR" that does both at once.
This is the genuine tradeoff of this design; it's worth it once you have
more than one service or more than a couple of people, but it's real
overhead, not a free lunch.

## Why the SRE report is split into two tiers

- **Every successful promotion** gets the lightweight **promotion report**
  (in the PR body) — changelog, test results, rollback pointer. Fully
  auto-generated, because it's all objective data.
- **Only an actual failure** (failed apply, failed smoke test) triggers the
  **full post-mortem scaffold**, using the org's incident template. It is
  deliberately left half-empty: metadata, timeline-of-what-the-pipeline-did,
  and links are filled in; root cause, five whys, lessons learned, and
  sign-off are left as `<TODO>` because those require a human who actually
  investigated, not a template guessing at judgment calls.

## Outlook — reasonable next steps

1. **Collapse `config/project.yaml` into one place.** Right now it's
   manually duplicated between app and infra repos.
2. **Add real health checks beyond "file exists."**
3. **Multiple runners**, as covered in earlier design discussion.
4. **Formalize the GitHub App's permissions with a written audit.**
5. **Tune the poll interval.** 10 minutes is a starting guess — watch how
   often it matters in practice and adjust.
6. **Consider Workload Identity Federation for the runner.**
7. **Add branch protection + required status checks** on all three repos.
8. **Actually test a GitLab port of one repo** (the app repo's `ci.yml` is
   the smallest, most self-contained candidate) to validate the "seams
   only" claim in practice rather than by inspection alone.
