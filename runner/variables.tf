variable "zone" {
  description = "GCP zone for the runner VM."
  type        = string
  default     = "me-west1-a"
}

variable "machine_type" {
  description = "Machine type for the runner VM. e2-small (2GB RAM) is the practical cost floor - e2-micro (1GB) risks OOM during Docker builds and pip installs."
  type        = string
  default     = "e2-small"
}

variable "runner_version" {
  description = "Version of the GitHub Actions runner package to install."
  type        = string
  default     = "2.319.1"
}

variable "github_pat_secret_id" {
  description = <<-EOT
    Name of the Secret Manager secret holding a GitHub fine-grained PAT with
    "Administration: Read and write" on all three repos (app, infra,
    environments) - used solely to mint short-lived runner registration
    tokens on boot. The secret VALUE is created out-of-band (see README.md).
  EOT
  type        = string
  default     = "github-actions-runner-pat"
}
