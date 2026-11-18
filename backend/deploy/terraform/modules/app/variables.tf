variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "environment" {
  description = "staging or prod."
  type        = string
}

variable "aspnet_environment" {
  description = "ASPNETCORE_ENVIRONMENT. Never Development or Testing (those relax the startup checks)."
  type        = string
  default     = "Production"

  validation {
    condition     = !contains(["Development", "Testing"], var.aspnet_environment)
    error_message = "aspnet_environment must not be Development or Testing."
  }
}

variable "image" {
  description = "Container image pinned by digest (registry/path@sha256:...). Prod promotes the digest that passed staging."
  type        = string

  validation {
    condition     = can(regex("@sha256:[0-9a-f]{64}$", var.image))
    error_message = "image must be pinned by digest (name@sha256:<64 hex>)."
  }
}

variable "api_service_account" {
  type = string
}

variable "worker_service_account" {
  type = string
}

variable "migrator_service_account" {
  type = string
}

variable "network_id" {
  type = string
}

variable "subnet_name" {
  type = string
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "api_min_instances" {
  description = "At least 2 for HA (topology in deployment section 3)."
  type        = number
  default     = 2
}

variable "api_max_instances" {
  type    = number
  default = 6
}

variable "api_cpu" {
  description = "Cloud Run needs >= 1 vCPU for concurrent requests; 0.5 vCPU from the design is rounded up."
  type        = string
  default     = "1"
}

variable "api_memory" {
  type    = string
  default = "512Mi"
}

variable "worker_cpu" {
  type    = string
  default = "1"
}

variable "worker_memory" {
  type    = string
  default = "512Mi"
}

# --- values produced by the other modules ---

variable "kms_provider" {
  description = "Value of Kms:Provider. The GCP adapter name is fixed by T-140's implementation; the default is a placeholder."
  type        = string
  default     = "GcpKms"
}

variable "kms_signing_keys" {
  description = "kid => { purpose, key_ref } from the kms module."
  type = map(object({
    purpose = string
    key_ref = string
  }))
}

variable "signing_key_status" {
  description = "kid => Next | Active | Retired. Unlisted kids are Active. Exactly one Active per purpose."
  type        = map(string)
  default     = {}
}

variable "kms_hmac_key_refs" {
  type = object({
    Seat              = string
    Audit             = string
    InstallHashPepper = string
  })
}

variable "kms_envelope_key_ref" {
  type = string
}

variable "kseat_check_hex" {
  description = "64 lower-case hex: HMAC-SHA256(K_seat, \"zaghlol-kseat-check-v1\"), from scripts/seat-check.sh after the first apply. Not a secret."
  type        = string
  default     = ""

  validation {
    condition     = var.kseat_check_hex == "" || can(regex("^[0-9a-f]{64}$", var.kseat_check_hex))
    error_message = "kseat_check_hex must be empty (first apply) or 64 lower-case hex characters."
  }
}

variable "rtdn" {
  description = "Rtdn:* settings from the pubsub module."
  type = object({
    audience             = string
    push_service_account = string
    subscription         = string
  })
}

variable "forwarded_headers_known_networks" {
  description = <<-EOT
    ForwardedHeaders:KnownNetworks. Behind the external Application Load Balancer the hop in front of Cloud Run is a
    Google front end; the defaults are Google's documented LB/health-check ranges plus the link-local range Cloud Run
    uses. VERIFY in staging from two client networks (deployment section 5) before prod; the API refuses to start with none.
  EOT
  type        = list(string)
  default     = ["130.211.0.0/22", "35.191.0.0/16", "169.254.0.0/16"]
}

variable "app_settings" {
  description = <<-EOT
    Non-secret application settings for API and worker, as environment variables with double underscores, e.g.
    Purchases__Google__PackageName, Purchases__Apple__BundleId, Attestation__AppAttest__TeamId, OperatorAuth__Issuer.
    Never put a credential here: use the Secret Manager secrets this module creates.
  EOT
  type        = map(string)
  default     = {}
}
