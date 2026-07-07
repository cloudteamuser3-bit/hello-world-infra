variable "image_digest" {
  description = "Image digest (sha256:...) to deploy - passed by the CI pipeline, sourced from the environments repo's prod.yaml."
  type        = string
}
