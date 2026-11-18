variable "project_id" {
  description = "One GCP project per environment (staging, prod)."
  type        = string
}

variable "region" {
  description = "Primary region. Recommended: europe-west3 (Frankfurt). See docs/03-technical/hosting-options.md."
  type        = string
  default     = "europe-west3"
}

variable "environment" {
  type = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be staging or prod."
  }
}

variable "hostname" {
  type = string
}

variable "image" {
  description = "Image pinned by digest."
  type        = string
}

variable "aspnet_environment" {
  type    = string
  default = "Production"
}

variable "high_availability" {
  description = "Zone-redundant database, 2+ API instances, deletion protection. true for prod."
  type        = bool
  default     = true
}

variable "db_edition" {
  type    = string
  default = "ENTERPRISE_PLUS"
}

variable "db_tier" {
  type    = string
  default = "db-perf-optimized-N-2"
}

variable "db_pitr_days" {
  type    = number
  default = 14
}

variable "signing_keys" {
  type = map(object({
    purpose = string
  }))
  default = {
    "e0001a" = { purpose = "Entitlement" }
    "s0001a" = { purpose = "Sync" }
  }
}

variable "signing_key_status" {
  type    = map(string)
  default = {}
}

variable "kseat_check_hex" {
  type    = string
  default = ""
}

variable "app_settings" {
  description = "Non-secret application settings (Purchases__*, Attestation__*, OperatorAuth__* ...). No credentials."
  type        = map(string)
  default     = {}
}

variable "forwarded_headers_known_networks" {
  type    = list(string)
  default = ["130.211.0.0/22", "35.191.0.0/16", "169.254.0.0/16"]
}

variable "api_max_instances" {
  type    = number
  default = 6
}
