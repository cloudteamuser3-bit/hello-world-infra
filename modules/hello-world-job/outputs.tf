output "bucket_name" {
  value = google_storage_bucket.output.name
}

output "job_name" {
  value = google_cloud_run_v2_job.hello_world.name
}

output "job_service_account_email" {
  value = google_service_account.job.email
}
