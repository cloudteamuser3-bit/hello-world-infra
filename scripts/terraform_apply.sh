#!/usr/bin/env bash
# Applies Terraform for a given environment. Terraform itself has always
# been platform-agnostic - this script just wraps init/plan/apply so no CI
# YAML has to know the actual command sequence.
#
# Usage: terraform_apply.sh <env> <image_digest>
set -euo pipefail

ENV="${1:?Usage: terraform_apply.sh <env> <image_digest>}"
IMAGE_DIGEST="${2:?missing image_digest}"

cd "environments/${ENV}"
terraform init -input=false >&2
terraform plan -input=false -var="image_digest=${IMAGE_DIGEST}" -out=tfplan >&2
terraform apply -input=false -auto-approve tfplan >&2

echo "BUCKET_NAME=$(terraform output -raw bucket_name)"
echo "JOB_NAME=$(terraform output -raw job_name)"
