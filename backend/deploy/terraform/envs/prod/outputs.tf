output "load_balancer_ip" {
  value = module.environment.load_balancer_ip
}

output "artifact_registry" {
  value = module.environment.artifact_registry
}

output "api_service_account" {
  value = module.environment.api_service_account
}

output "worker_service_account" {
  value = module.environment.worker_service_account
}

output "rtdn_topic" {
  value = module.environment.rtdn_topic
}

output "db_private_ip" {
  value = module.environment.db_private_ip
}

output "secret_ids" {
  value = module.environment.secret_ids
}

output "signing_keys" {
  value = module.environment.signing_keys
}

output "hmac_key_refs" {
  value = module.environment.hmac_key_refs
}

output "api_service_name" {
  value = module.environment.api_service_name
}

output "worker_pool_name" {
  value = module.environment.worker_pool_name
}

output "migrate_job_name" {
  value = module.environment.migrate_job_name
}
