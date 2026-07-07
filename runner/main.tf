terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    bucket = "mafat-ai-gee-monitor-dev-cicd-tfstate"
    prefix = "hello-world/runner"
  }
}

locals {
  config = yamldecode(file("${path.module}/../config/project.yaml"))
  repos = [
    local.config.github.app_repo,
    local.config.github.infra_repo,
    local.config.github.environments_repo,
  ]
}

provider "google" {
  project = local.config.project.gcp_project_id
  region  = local.config.project.region
}

# --- One service account for the VM. It needs the UNION of what all three ---
# --- repos' pipelines will do on this machine, since all three repos'    ---
# --- runner processes share this one machine and its one attached SA.   ---
resource "google_service_account" "runner" {
  account_id   = "gh-actions-runner"
  display_name = "GitHub Actions self-hosted runner (app+infra+environments)"
}

resource "google_project_iam_member" "runner_roles" {
  for_each = toset([
    "roles/artifactregistry.writer",  # app repo: push images
    "roles/storage.admin",            # infra repo: manage buckets
    "roles/run.admin",                # infra repo: manage Cloud Run Jobs
    "roles/iam.serviceAccountAdmin",  # infra repo: create per-job service accounts
    "roles/iam.serviceAccountUser",   # infra repo: attach those service accounts
    "roles/logging.logWriter",        # all repos: ship logs
  ])
  project = local.config.project.gcp_project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.runner.email}"
}

# --- Secret Manager container for the GitHub PAT used to mint runner ---
# --- registration tokens for all three repos. Needs "Administration:   ---
# --- Read and write" on each of the three repos (fine-grained PAT).    ---
resource "google_secret_manager_secret" "github_pat" {
  secret_id = var.github_pat_secret_id

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_iam_member" "runner_secret_accessor" {
  secret_id = google_secret_manager_secret.github_pat.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runner.email}"
}

resource "google_compute_instance" "runner" {
  name         = "gh-actions-runner-01"
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 50
    }
  }

  network_interface {
    network = "default"
  }

  service_account {
    email  = google_service_account.runner.email
    scopes = ["cloud-platform"]
  }

  metadata_startup_script = templatefile("${path.module}/scripts/startup-script.sh.tpl", {
    github_owner         = local.config.github.org
    repos                = join(" ", local.repos)
    runner_version       = var.runner_version
    github_pat_secret_id = var.github_pat_secret_id
    project_id           = local.config.project.gcp_project_id
  })

  metadata = {
    startup-script-run-on-reboot = "true"
  }

  allow_stopping_for_update = true

  labels = {
    purpose = "github-actions-runner"
  }
}

# --- Cloud NAT for Internet egress from strictly private runner VM ---
resource "google_compute_router" "router" {
  name    = "router-default-me-west1"
  region  = local.config.project.region
  network = "default"
}

resource "google_compute_router_nat" "nat" {
  name                               = "nat-default-me-west1"
  router                             = google_compute_router.router.name
  region                             = google_compute_router.router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
