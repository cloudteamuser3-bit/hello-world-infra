terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # Each environment has its own state file in its own GCS prefix - this is
  # what makes it physically impossible to apply a dev plan against prod's
  # state. Create the state bucket itself once, by hand, before first apply:
  #   gsutil mb -l me-west1 gs://mafat-ai-gee-monitor-dev-cicd-tfstate
  #   gsutil versioning set on gs://mafat-ai-gee-monitor-dev-cicd-tfstate
  backend "gcs" {
    bucket = "mafat-ai-gee-monitor-dev-cicd-tfstate"
    prefix = "hello-world/staging"
  }
}

locals {
  config = yamldecode(file("${path.module}/../../config/project.yaml"))
}

provider "google" {
  project = local.config.project.gcp_project_id
  region  = local.config.project.region
}

module "hello_world_job" {
  source = "../../modules/hello-world-job"

  environment     = "staging"
  region          = local.config.project.region
  bucket_name     = "${local.config.project.gcp_project_id}-hello-world-${local.config.environments.staging.bucket_suffix}"
  job_name        = local.config.cloud_run_job.name
  image           = "${local.config.project.region}-docker.pkg.dev/${local.config.project.gcp_project_id}/${local.config.artifact_registry.repository}/${local.config.artifact_registry.image_name}@${var.image_digest}"
  file_name       = local.config.file_output.file_name
  cpu             = local.config.cloud_run_job.cpu
  memory          = local.config.cloud_run_job.memory
  timeout_seconds = local.config.cloud_run_job.timeout_seconds
  max_retries     = local.config.cloud_run_job.max_retries
}
