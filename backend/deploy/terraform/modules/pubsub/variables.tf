variable "project_id" {
  type = string
}

variable "region" {
  description = "Region the topic's messages may be stored in (message storage policy)."
  type        = string
}

variable "environment" {
  type = string
}

variable "push_endpoint" {
  description = "Full HTTPS URL of POST /v1/notifications/google, e.g. https://api.zaghlol.app/v1/notifications/google."
  type        = string

  validation {
    condition     = startswith(var.push_endpoint, "https://")
    error_message = "push_endpoint must be an https URL."
  }
}
