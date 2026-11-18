variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "environment" {
  type = string
}

variable "private_network" {
  description = "VPC id with private services access already connected (network module output private_services_network)."
  type        = string
}

variable "edition" {
  description = "ENTERPRISE (PITR log retention 1-7 days) or ENTERPRISE_PLUS (1-35 days). The 14-day PITR in deployment section 4 needs ENTERPRISE_PLUS."
  type        = string
  default     = "ENTERPRISE_PLUS"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "tier" {
  description = "Machine tier. ENTERPRISE_PLUS needs db-perf-optimized-N-*; ENTERPRISE uses db-custom-* or db-g1-small."
  type        = string
  default     = "db-perf-optimized-N-2"
}

variable "availability_type" {
  description = "REGIONAL (zone-redundant HA) for prod; ZONAL is acceptable for staging."
  type        = string
  default     = "REGIONAL"
}

variable "disk_size_gb" {
  type    = number
  default = 20
}

variable "pitr_retention_days" {
  description = "Transaction log retention. 14 days per deployment section 4."
  type        = number
  default     = 14
}

variable "retained_backups" {
  type    = number
  default = 14
}

variable "deletion_protection" {
  description = "Protects the instance from tofu destroy and from the API."
  type        = bool
  default     = true
}
