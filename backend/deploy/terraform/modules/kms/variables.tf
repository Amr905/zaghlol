variable "project_id" {
  description = "GCP project that owns the key ring."
  type        = string
}

variable "location" {
  description = "KMS location (same region as the rest of the stack, e.g. europe-west3)."
  type        = string
}

variable "environment" {
  description = "staging or prod. Part of the key ring name."
  type        = string
}

variable "signing_keys" {
  description = <<-EOT
    Signing keys by kid (backend-api / deployment section 3: ^[se][0-9]{4}[a-z]$; s = Sync, e = Entitlement).
    Add a new kid for a rotation; never delete an old one while apps in the field still trust it.
  EOT
  type = map(object({
    purpose = string # "Sync" or "Entitlement"
  }))
  default = {
    "e0001a" = { purpose = "Entitlement" }
    "s0001a" = { purpose = "Sync" }
  }

  validation {
    condition     = alltrue([for k, v in var.signing_keys : can(regex("^[se][0-9]{4}[a-z]$", k)) && contains(["Sync", "Entitlement"], v.purpose)])
    error_message = "Each kid must match ^[se][0-9]{4}[a-z]$ and have purpose Sync or Entitlement."
  }
}

variable "signing_protection_level" {
  description = "HSM or SOFTWARE for the ES256 signing keys."
  type        = string
  default     = "HSM"
}

variable "hmac_protection_level" {
  description = "HSM or SOFTWARE for the HMAC keys (K_seat, K_audit, install_hash pepper)."
  type        = string
  default     = "HSM"
}

variable "api_service_account" {
  description = "E-mail of the API runtime identity. May sign, MAC and wrap/unwrap; can never export key material."
  type        = string
}

variable "worker_service_account" {
  description = "E-mail of the worker runtime identity. Needs only the envelope key (Apple revocation retry unseals a refresh token)."
  type        = string
}

variable "labels" {
  type    = map(string)
  default = {}
}
