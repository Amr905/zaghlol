# One environment = one GCP project. Everything the Gold design needs, wired together.

locals {
  labels = {
    app         = "zaghlol"
    environment = var.environment
  }

  apis = [
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "servicenetworking.googleapis.com",
    "compute.googleapis.com",
    "cloudkms.googleapis.com",
    "secretmanager.googleapis.com",
    "pubsub.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "artifactregistry.googleapis.com",
    "androidpublisher.googleapis.com",
    "playintegrity.googleapis.com",
  ]
}

resource "google_project_service" "this" {
  for_each = toset(local.apis)

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# --- runtime identities: three, so every grant can be least-privilege ---

resource "google_service_account" "api" {
  project      = var.project_id
  account_id   = "zaghlol-api"
  display_name = "Zaghlol API runtime (also the Play Console API user)"

  depends_on = [google_project_service.this]
}

resource "google_service_account" "worker" {
  project      = var.project_id
  account_id   = "zaghlol-worker"
  display_name = "Zaghlol worker runtime (also a Play Console API user)"

  depends_on = [google_project_service.this]
}

resource "google_service_account" "migrator" {
  project      = var.project_id
  account_id   = "zaghlol-migrator"
  display_name = "Zaghlol migration job"

  depends_on = [google_project_service.this]
}

resource "google_artifact_registry_repository" "images" {
  project       = var.project_id
  location      = var.region
  repository_id = "zaghlol"
  format        = "DOCKER"
  labels        = local.labels

  depends_on = [google_project_service.this]
}

module "network" {
  source = "../network"

  project_id  = var.project_id
  region      = var.region
  environment = var.environment

  depends_on = [google_project_service.this]
}

module "database" {
  source = "../database"

  project_id          = var.project_id
  region              = var.region
  environment         = var.environment
  private_network     = module.network.private_services_network
  edition             = var.db_edition
  tier                = var.db_tier
  pitr_retention_days = var.db_pitr_days
  availability_type   = var.high_availability ? "REGIONAL" : "ZONAL"
  deletion_protection = var.high_availability
}

module "kms" {
  source = "../kms"

  project_id             = var.project_id
  location               = var.region
  environment            = var.environment
  signing_keys           = var.signing_keys
  api_service_account    = google_service_account.api.email
  worker_service_account = google_service_account.worker.email
  labels                 = local.labels

  depends_on = [google_project_service.this]
}

module "pubsub" {
  source = "../pubsub"

  project_id    = var.project_id
  region        = var.region
  environment   = var.environment
  push_endpoint = "https://${var.hostname}/v1/notifications/google"

  depends_on = [google_project_service.this]
}

module "app" {
  source = "../app"

  project_id               = var.project_id
  region                   = var.region
  environment              = var.environment
  aspnet_environment       = var.aspnet_environment
  image                    = var.image
  api_service_account      = google_service_account.api.email
  worker_service_account   = google_service_account.worker.email
  migrator_service_account = google_service_account.migrator.email
  network_id               = module.network.network_id
  subnet_name              = module.network.subnet_name
  deletion_protection      = var.high_availability
  api_min_instances        = var.high_availability ? 2 : 1
  api_max_instances        = var.api_max_instances

  kms_signing_keys     = module.kms.signing_keys
  signing_key_status   = var.signing_key_status
  kms_hmac_key_refs    = module.kms.hmac_key_refs
  kms_envelope_key_ref = module.kms.envelope_key_ref
  kseat_check_hex      = var.kseat_check_hex

  rtdn = {
    audience             = module.pubsub.audience
    push_service_account = module.pubsub.push_service_account
    subscription         = module.pubsub.subscription_id
  }

  forwarded_headers_known_networks = var.forwarded_headers_known_networks
  app_settings                     = var.app_settings
}

module "edge" {
  source = "../edge"

  project_id             = var.project_id
  region                 = var.region
  environment            = var.environment
  hostname               = var.hostname
  api_service_name       = module.app.api_service_name
  assets_bucket_location = upper(substr(var.region, 0, 2))
  deletion_protection    = var.high_availability
}

# --- no query strings in any log (edge AC) ---
# Load balancer request logs are off on the backends; these exclusions also drop the Cloud Run request log, whose
# httpRequest.requestUrl carries the query string. Application logs (Serilog, no tokens/IPs/contributions) stay.

resource "google_logging_project_exclusion" "run_requests" {
  project     = var.project_id
  name        = "exclude-run-request-logs"
  description = "Cloud Run request logs contain the full URL including query strings."
  filter      = "log_id(\"run.googleapis.com/requests\")"
}

resource "google_logging_project_exclusion" "lb_requests" {
  project     = var.project_id
  name        = "exclude-lb-request-logs"
  description = "Belt and braces: load balancer request logs are disabled on the backends."
  filter      = "resource.type=\"http_load_balancer\""
}
