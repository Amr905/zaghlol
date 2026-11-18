variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "environment" {
  type = string
}

variable "subnet_cidr" {
  description = "Subnet for Cloud Run direct VPC egress. Needs room for instances x2 (a /26 is the minimum; /24 is generous)."
  type        = string
  default     = "10.20.0.0/24"
}

variable "private_service_prefix_length" {
  description = "Prefix length of the range reserved for Cloud SQL private services access."
  type        = number
  default     = 20
}
