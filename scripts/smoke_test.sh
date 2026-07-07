#!/usr/bin/env bash
# Runs the Cloud Run Job once and checks the expected file shows up in the
# bucket. Only assumes `gcloud`/`gsutil` are available - no CI platform
# dependency.
#
# Usage: smoke_test.sh <job_name> <region> <bucket_name> <file_name>
set -euo pipefail

JOB_NAME="${1:?}"
REGION="${2:?}"
BUCKET_NAME="${3:?}"
FILE_NAME="${4:-hello_world.txt}"

echo "==> Executing ${JOB_NAME}" >&2
gcloud run jobs execute "$JOB_NAME" --region "$REGION" --wait

echo "==> Verifying gs://${BUCKET_NAME}/${FILE_NAME}" >&2
if gsutil -q stat "gs://${BUCKET_NAME}/${FILE_NAME}"; then
  echo "PASSED=true"
else
  echo "PASSED=false"
  exit 1
fi
