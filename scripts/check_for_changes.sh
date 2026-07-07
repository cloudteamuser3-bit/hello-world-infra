#!/usr/bin/env bash
# Compares the environments repo's desired image_digest for <env> against
# this repo's own record of what was last successfully applied
# (.state/<env>.json). This replaces a platform-specific dispatch trigger
# with a plain git clone + file comparison - works identically on a
# schedule under any CI platform, or even run by hand from a cron job on a
# laptop.
#
# Usage: check_for_changes.sh <env>
# Requires: VCS_ORG, ENVIRONMENTS_REPO env vars (read-only clone, no token
# needed if the environments repo is public; use VCS_TOKEN if private)
set -euo pipefail

ENV="${1:?Usage: check_for_changes.sh <env>}"
: "${VCS_ORG:?VCS_ORG must be set}"
: "${ENVIRONMENTS_REPO:?ENVIRONMENTS_REPO must be set}"

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

if [ -n "${VCS_TOKEN:-}" ]; then
  REPO_URL="https://x-access-token:${VCS_TOKEN}@github.com/${VCS_ORG}/${ENVIRONMENTS_REPO}.git"
else
  REPO_URL="https://github.com/${VCS_ORG}/${ENVIRONMENTS_REPO}.git"
fi

git clone --depth 1 --quiet "$REPO_URL" "$WORKDIR" >&2

DESIRED_DIGEST=$(python3 -c "import yaml; print(yaml.safe_load(open('$WORKDIR/environments/${ENV}.yaml')).get('image_digest',''))")
DESIRED_TAG=$(python3 -c "import yaml; print(yaml.safe_load(open('$WORKDIR/environments/${ENV}.yaml')).get('image_tag',''))")
PROMOTED_FROM=$(python3 -c "import yaml; print(yaml.safe_load(open('$WORKDIR/environments/${ENV}.yaml')).get('promoted_from',''))")

STATE_FILE=".state/${ENV}.json"
if [ -f "$STATE_FILE" ]; then
  APPLIED_DIGEST=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('applied_image_digest',''))")
else
  APPLIED_DIGEST=""
fi

if [ -z "$DESIRED_DIGEST" ]; then
  echo "CHANGED=false"
elif [ "$DESIRED_DIGEST" != "$APPLIED_DIGEST" ]; then
  echo "CHANGED=true"
else
  echo "CHANGED=false"
fi

echo "DESIRED_IMAGE_TAG=${DESIRED_TAG}"
echo "DESIRED_IMAGE_DIGEST=${DESIRED_DIGEST}"
echo "PROMOTED_FROM=${PROMOTED_FROM}"
