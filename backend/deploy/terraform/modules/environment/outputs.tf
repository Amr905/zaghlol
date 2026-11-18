output "load_balancer_ip" {
  value = module.edge.load_balancer_ip
}

output "artifact_registry" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}"
}

output "api_service_account" {
  description = "Invite this e-mail in Play Console > Users and permissions (orders + subscriptions on this app)."
  value       = google_service_account.api.email
}

output "worker_service_account" {
  description = "Also invite this e-mail in Play Console (it runs the ack sweeper and the RTDN processor)."
  value       = google_service_account.worker.email
}

output "rtdn_topic" {
  description = "Paste into Play Console > Monetization setup > Real-time developer notifications."
  value       = module.pubsub.topic_name
}

output "db_connection_name" {
  value = module.database.connection_name
}

output "db_private_ip" {
  value = module.database.private_ip_address
}

output "secret_ids" {
  value = module.app.secret_ids
}

output "signing_keys" {
  value = module.kms.signing_keys
}

output "hmac_key_refs" {
  value = module.kms.hmac_key_refs
}

output "api_service_name" {
  value = module.app.api_service_name
}

output "worker_pool_name" {
  value = module.app.worker_pool_name
}

output "migrate_job_name" {
  value = module.app.migrate_job_name
}
