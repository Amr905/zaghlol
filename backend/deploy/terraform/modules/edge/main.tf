# Global external Application Load Balancer + Cloud Armor + Cloud CDN for the static bucket.
#
# Logging (T-140, edge AC): request logging is OFF on every backend, Cloud Armor logs at NORMAL (no matched field values,
# so no request body or query sample), and the environment module adds project log exclusions for the load balancer and the
# Cloud Run request logs, whose entries would otherwise carry the full URL including any query string.

resource "google_compute_global_address" "this" {
  project = var.project_id
  name    = "zaghlol-${var.environment}-lb"
}

resource "google_compute_region_network_endpoint_group" "api" {
  project               = var.project_id
  name                  = "zaghlol-${var.environment}-api-neg"
  region                = var.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = var.api_service_name
  }
}

resource "google_compute_security_policy" "this" {
  project = var.project_id
  name    = "zaghlol-${var.environment}-edge"

  advanced_options_config {
    log_level = "NORMAL"
  }

  # Preconfigured OWASP rules are intentionally not enabled: they inspect bodies and would false-positive on JWS payloads
  # for /v1/apple/* and /v1/notifications/*. Add them only with exclusions for those paths (T-140 design note).
  rule {
    action   = "throttle"
    priority = 1000
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      rate_limit_threshold {
        count        = var.rate_limit_per_minute
        interval_sec = 60
      }
    }
  }

  rule {
    action   = "allow"
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }
}

resource "google_compute_backend_service" "api" {
  project               = var.project_id
  name                  = "zaghlol-${var.environment}-api"
  protocol              = "HTTPS"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  security_policy       = google_compute_security_policy.this.id

  backend {
    group = google_compute_region_network_endpoint_group.api.id
  }

  log_config {
    enable = false
  }
}

# --- catalog snapshots, signed .shortcut, store-review media (public by design; every payload is signed) ---

resource "google_storage_bucket" "assets" {
  project                     = var.project_id
  name                        = "zaghlol-${var.environment}-assets-${var.project_id}"
  location                    = var.assets_bucket_location
  uniform_bucket_level_access = true
  force_destroy               = !var.deletion_protection

  versioning {
    enabled = true
  }
}

resource "google_storage_bucket_iam_member" "assets_public_read" {
  bucket = google_storage_bucket.assets.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

resource "google_compute_backend_bucket" "assets" {
  project     = var.project_id
  name        = "zaghlol-${var.environment}-assets"
  bucket_name = google_storage_bucket.assets.name
  enable_cdn  = true

  cdn_policy {
    cache_mode  = "CACHE_ALL_STATIC"
    default_ttl = 3600
    max_ttl     = 86400
  }
}

resource "google_compute_url_map" "https" {
  project         = var.project_id
  name            = "zaghlol-${var.environment}"
  default_service = google_compute_backend_service.api.id

  host_rule {
    hosts        = [var.hostname]
    path_matcher = "main"
  }

  path_matcher {
    name            = "main"
    default_service = google_compute_backend_service.api.id

    path_rule {
      paths   = ["/assets/*"]
      service = google_compute_backend_bucket.assets.id
    }
  }
}

resource "google_compute_managed_ssl_certificate" "this" {
  project = var.project_id
  name    = "zaghlol-${var.environment}-cert"

  managed {
    domains = [var.hostname]
  }
}

resource "google_compute_ssl_policy" "modern" {
  project         = var.project_id
  name            = "zaghlol-${var.environment}-tls"
  profile         = "MODERN"
  min_tls_version = "TLS_1_2"
}

resource "google_compute_target_https_proxy" "this" {
  project          = var.project_id
  name             = "zaghlol-${var.environment}-https"
  url_map          = google_compute_url_map.https.id
  ssl_certificates = [google_compute_managed_ssl_certificate.this.id]
  ssl_policy       = google_compute_ssl_policy.modern.id
}

resource "google_compute_global_forwarding_rule" "https" {
  project               = var.project_id
  name                  = "zaghlol-${var.environment}-https"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  target                = google_compute_target_https_proxy.this.id
  port_range            = "443"
  ip_address            = google_compute_global_address.this.id
}

resource "google_compute_url_map" "redirect" {
  project = var.project_id
  name    = "zaghlol-${var.environment}-redirect"

  default_url_redirect {
    https_redirect = true
    strip_query    = false
  }
}

resource "google_compute_target_http_proxy" "redirect" {
  project = var.project_id
  name    = "zaghlol-${var.environment}-http"
  url_map = google_compute_url_map.redirect.id
}

resource "google_compute_global_forwarding_rule" "http" {
  project               = var.project_id
  name                  = "zaghlol-${var.environment}-http"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  target                = google_compute_target_http_proxy.redirect.id
  port_range            = "80"
  ip_address            = google_compute_global_address.this.id
}
