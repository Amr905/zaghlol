variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "environment" {
  type = string
}

variable "hostname" {
  description = "Public API host, e.g. api.zaghlol.app (prod) or api.staging.zaghlol.app."
  type        = string
}

variable "api_service_name" {
  description = "Cloud Run service behind the load balancer."
  type        = string
}

variable "assets_bucket_location" {
  description = "Location of the catalog/shortcut bucket (EU multi-region or the region)."
  type        = string
}

variable "rate_limit_per_minute" {
  description = "Per-client-IP request budget at the edge (the app has its own per-network limits)."
  type        = number
  default     = 600
}

variable "deletion_protection" {
  type    = bool
  default = true
}
