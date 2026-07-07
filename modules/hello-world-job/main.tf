terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# --- Dedicated service account for the job. Least privilege: it can only ---
# --- write to its own environment's bucket, nothing else in the project. ---
resource "google_service_account" "job" {
  account_id   = "hello-world-job-${var.environment}"
  display_name = "hello-world-job (${var.environment})"
}

resource "google_storage_bucket" "output" {
  name                        = var.bucket_name
  location                    = var.region
  force_destroy               = var.environment != "prod" # allow easy teardown of dev/staging; protect prod
  uniform_bucket_level_access = true

  versioning {
    enabled = var.environment == "prod" # keep history of hello_world.txt overwrites in prod only
  }

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

resource "google_storage_bucket_iam_member" "job_writer" {
  bucket = google_storage_bucket.output.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.job.email}"
}

resource "google_cloud_run_v2_job" "hello_world" {
  name     = "${var.job_name}-${var.environment}"
  location = var.region

  template {
    template {
      service_account = google_service_account.job.email
      timeout         = "${var.timeout_seconds}s"
      max_retries     = var.max_retries

      containers {
        image = var.image
        resources {
          limits = {
            cpu    = var.cpu
            memory = var.memory
          }
        }
        env {
          name  = "BUCKET_NAME"
          value = google_storage_bucket.output.name
        }
        env {
          name  = "FILE_NAME"
          value = var.file_name
        }
        env {
          name  = "ENVIRONMENT"
          value = var.environment
        }
      }
    }
  }

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }

  lifecycle {
    # The image is a moving target driven by the environments repo, not by
    # hand-editing Terraform - re-applying with a new `image` value is the
    # expected, routine way this resource changes.
    create_before_destroy = false
  }
}
