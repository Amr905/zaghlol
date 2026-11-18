module "environment" {
  source = "../../modules/environment"

  project_id         = var.project_id
  region             = var.region
  environment        = "prod"
  aspnet_environment = "Production"
  hostname           = var.hostname
  image              = var.image

  high_availability  = true
  db_edition         = "ENTERPRISE_PLUS"
  db_tier            = "db-perf-optimized-N-2"
  db_pitr_days       = 14
  api_max_instances  = 6
  kseat_check_hex    = var.kseat_check_hex
  app_settings       = var.app_settings
  signing_key_status = var.signing_key_status
}
