module "environment" {
  source = "../../modules/environment"

  project_id         = var.project_id
  region             = var.region
  environment        = "staging"
  aspnet_environment = "Staging"
  hostname           = var.hostname
  image              = var.image

  # Cheaper staging: zonal database, 1 API instance, Enterprise edition with 7-day PITR.
  high_availability  = false
  db_edition         = "ENTERPRISE"
  db_tier            = "db-custom-1-3840"
  db_pitr_days       = 7
  api_max_instances  = 2
  kseat_check_hex    = var.kseat_check_hex
  app_settings       = var.app_settings
  signing_key_status = var.signing_key_status
}
