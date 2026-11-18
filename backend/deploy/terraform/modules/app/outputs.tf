output "api_service_name" {
  value = google_cloud_run_v2_service.api.name
}

output "worker_pool_name" {
  value = google_cloud_run_v2_worker_pool.worker.name
}

output "migrate_job_name" {
  value = google_cloud_run_v2_job.migrate.name
}

output "secret_ids" {
  description = "Empty secrets the operator must give a first version (README, First deploy)."
  value       = { for k, s in google_secret_manager_secret.this : k => s.secret_id }
}
