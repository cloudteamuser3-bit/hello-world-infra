variable "environment" {
  description = "Environment name: dev, staging, or prod."
  type        = string
}

variable "region" {
  type = string
}

variable "bucket_name" {
  description = "Globally-unique GCS bucket name for this environment."
  type        = string
}

variable "job_name" {
  description = "Base name for the Cloud Run Job (environment suffix is added automatically)."
  type        = string
}

variable "image" {
  description = "Full Artifact Registry image reference, including digest, e.g. region-docker.pkg.dev/project/repo/image@sha256:..."
  type        = string
}

variable "file_name" {
  type    = string
  default = "hello_world.txt"
}

variable "cpu" {
  type    = string
  default = "1"
}

variable "memory" {
  type    = string
  default = "512Mi"
}

variable "timeout_seconds" {
  type    = number
  default = 300
}

variable "max_retries" {
  type    = number
  default = 1
}
