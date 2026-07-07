#!/usr/bin/env python3
"""Auto-scaffold an SRE post-mortem from the org's standard template.

This deliberately does NOT try to write the whole report. It fills in only
the fields that are objectively knowable from this workflow run (metadata,
timestamps, what the pipeline actually did). Everything that requires human
judgment or investigation - root cause, five whys, lessons learned, sign-off
- is left as the template's own placeholder text, so a human opens a
partially-done report, not a blank page and not a fake-finished one.

Fires only on a failed deploy/smoke-test (see apply-environment.yml's
report-failure job) - never on a routine successful promotion, which gets
the much lighter promotion-report instead.
"""

from __future__ import annotations

import argparse
from datetime import UTC, datetime


TEMPLATE = """\
# SRE Incident Post-Mortem Report

> **Classification:** CONFIDENTIAL — Internal Use Only
> **Template Version:** v2.0
> **Status:** AUTO-SCAFFOLDED — sections marked `<TODO>` require human input before this is complete.

---

## 1 · Incident Metadata

| Field | Value |
|---|---|
| **Incident ID** | `<TODO: assign INC-YYYY-NNNN>` |
| **Incident Title** | `<TODO: concise description of what broke>` |
| **Service(s) Affected** | `{job_name}` |
| **Environment** | {environment} |
| **Cloud Provider / Region** | GCP · see `config/project.yaml` |
| **Date (UTC)** | {date} |
| **Detected (UTC)** | {time} (pipeline failure) |
| **Declared (UTC)** | `<TODO>` |
| **Mitigated (UTC)** | `<TODO>` |
| **Resolved (UTC)** | `<TODO>` |
| **Report Author** | `<TODO>` |
| **Report Date** | {date} |
| **Report Version** | v1.0 (auto-scaffolded, unreviewed) |

### Severity Classification

**Selected severity: `<TODO — SEV-1/2/3/4>`**

This was a **pipeline-detected** failure (deploy or automated smoke test
failed), not yet a confirmed user-facing incident. Assess actual severity
before treating this as a customer-impacting event.

### Incident Roles

| Role | Name |
|---|---|
| **Incident Commander (IC)** | `<TODO>` |
| **Tech Lead** | `<TODO>` |
| **Scribe** | `<TODO>` |

---

## 2 · Executive Summary

`<TODO — 3-5 sentences, no jargon, for leadership/non-technical readers>`

| Field | Value |
|---|---|
| **User-visible symptom** | `<TODO>` |
| **SLO breached?** | `<TODO>` |
| **Repeat incident?** | `<TODO>` |

---

## 3 · Detection & Alerting

| Field | Value |
|---|---|
| **Alert tool** | GitHub Actions (this pipeline) |
| **Alert name** | `apply-environment` workflow failure |
| **Detected via** | Automated post-deploy smoke test (Cloud Run Job execution + bucket file check) |
| **Failed at (UTC)** | {time} |
| **Workflow run** | {run_url} |

### Detection Quality Analysis

- [ ] Were there precursor signals before this failed? `<TODO>`
- [ ] Was this the fastest possible detection point, or could an earlier
      check have caught it? `<TODO>`

---

## 4 · Incident Timeline

> Auto-filled from what the pipeline did. Add human response actions below.

| Time (UTC) | Type | Event / Action Taken | Actor |
|---|---|---|---|
| {time} | `ALERT` | `apply-environment` workflow failed for **{environment}**, deploying image `{image_tag}` (digest `{image_digest}`) | GitHub Actions |
| `<TODO>` | `ACK` | `<TODO — who acknowledged, when>` | `<TODO>` |
| `<TODO>` | `TRIAGE` | `<TODO>` | `<TODO>` |
| `<TODO>` | `ACTION` | `<TODO>` | `<TODO>` |
| `<TODO>` | `RESOLVE` | `<TODO>` | `<TODO>` |

**Full pipeline logs:** {run_url}

---

## 5 · Impact Assessment

- **Environment:** {environment}
- **Service:** {job_name}
- **Note:** because this is a batch job (Cloud Run Job), not a live
  request-serving service, "impact" here likely means the scheduled/expected
  file write did not happen - assess downstream consumers of the bucket
  output, if any. `<TODO>`

---

## 6 · SLI, SLO & Error Budget

`<TODO — fill in if this environment/job has defined SLOs>`

---

## 7 · Root Cause Analysis

### 7.1 Root Cause Statement

`<TODO — name the specific component, config value, or code path. Check the workflow run logs linked above as a starting point:>` {run_url}

### 7.2 Contributing Factors

- `<TODO>`

### 7.3 Five Whys

| | Question | Answer |
|---|---|---|
| **Why 1** | Why did the deploy/smoke test fail? | `<TODO>` |
| **Why 2** | `<TODO>` | `<TODO>` |
| **Why 3** | `<TODO>` | `<TODO>` |
| **Why 4** | `<TODO>` | `<TODO>` |
| **Why 5 (Root)** | `<TODO>` | `<TODO — systemic root cause>` |

---

## 8 · Mitigation & Resolution

| Field | Value |
|---|---|
| **Rollback available** | Previous known-good tag is recorded in `environments/{environment}.yaml`'s git history in the environments repo |
| **Rollback executed?** | `<TODO>` |
| **Resolution verified by** | `<TODO>` |

---

## 9 · Communication Log

`<TODO — fill in if this required any human-facing communication>`

---

## 10 · Lessons Learned

### What Went Well ✅
`<TODO>`

### What Went Wrong ❌
`<TODO>`

### Where Did We Get Lucky 🍀
`<TODO>`

---

## 11 · Action Items & Follow-ups

| # | Action Item | Owner | Due | Pri | Status |
|---|---|---|---|---|---|
| 1 | `<TODO>` | `<TODO>` | `<TODO>` | `<TODO>` | Open |

---

## 12 · Prevention & Systemic Improvements

`<TODO>`

---

## 13 · Sign-off & Approvals

| Role | Name | Date | Status |
|---|---|---|---|
| Report Author | `<TODO>` | `<TODO>` | Pending |
| Incident Commander | `<TODO>` | `<TODO>` | Pending |

---

> **Document Control**
> This report was auto-scaffolded by `scripts/generate_postmortem.py` from the
> `apply-environment` workflow's failure. It is intentionally incomplete —
> every `<TODO>` requires a human to fill it in before this counts as a
> finished post-mortem.
"""


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--environment", required=True)
    parser.add_argument("--image-tag", required=True)
    parser.add_argument("--image-digest", required=True)
    parser.add_argument("--run-url", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    now = datetime.now(UTC)
    job_name = f"hello-world-job-{args.environment}"

    content = TEMPLATE.format(
        environment=args.environment,
        image_tag=args.image_tag,
        image_digest=args.image_digest or "(none captured)",
        run_url=args.run_url,
        job_name=job_name,
        date=now.strftime("%Y-%m-%d"),
        time=now.strftime("%H:%M:%S UTC"),
    )

    with open(args.output, "w") as f:
        f.write(content)


if __name__ == "__main__":
    main()
