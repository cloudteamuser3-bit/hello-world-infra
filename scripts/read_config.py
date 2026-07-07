#!/usr/bin/env python3
"""Read config/project.yaml and print KEY=VALUE lines.

Deliberately platform-agnostic: no $GITHUB_OUTPUT, no CI-specific env vars.
Usage from any CI system or a local shell:

    eval "$(python3 scripts/read_config.py)"
    echo "$GCP_PROJECT_ID"

Or, on platforms with a native "write to job output" mechanism (GitHub
Actions' $GITHUB_OUTPUT, GitLab's dotenv artifacts), redirect this script's
output into that mechanism instead - the parsing logic itself never changes.
"""

from pathlib import Path

import yaml


def main() -> None:
    config_path = Path(__file__).resolve().parent.parent / "config" / "project.yaml"
    with open(config_path) as f:
        cfg = yaml.safe_load(f)

    print(f"GCP_PROJECT_ID={cfg['project']['gcp_project_id']}")
    print(f"REGION={cfg['project']['region']}")
    print(f"AR_REPOSITORY={cfg['artifact_registry']['repository']}")
    print(f"IMAGE_NAME={cfg['artifact_registry']['image_name']}")
    print(f"VCS_ORG={cfg['github']['org']}")
    print(f"ENVIRONMENTS_REPO={cfg['github']['environments_repo']}")
    print(f"INFRA_REPO={cfg['github']['infra_repo']}")
    print(f"APP_REPO={cfg['github']['app_repo']}")


if __name__ == "__main__":
    main()
