variable "image_digest" {
  description = "Image digest (sha256:...) to deploy - passed by the CI pipeline, sourced from the environments repo's staging.yaml."
  type        = string
}
