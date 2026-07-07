output "runner_service_account_email" {
  value = google_service_account.runner.email
}

output "runner_instance_name" {
  value = google_compute_instance.runner.name
}

output "registered_repos" {
  value = local.repos
}
