variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "europe-west3"
}

variable "hostname" {
  type = string
}

variable "image" {
  description = "Image pinned by digest, passed by the deploy workflow."
  type        = string
}

variable "kseat_check_hex" {
  type    = string
  default = ""
}

variable "app_settings" {
  type    = map(string)
  default = {}
}

variable "signing_key_status" {
  type    = map(string)
  default = {}
}
