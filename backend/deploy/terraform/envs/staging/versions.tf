terraform {
  required_version = ">= 1.8.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.40, < 8.0"
    }
  }

  # Partial configuration: the bucket (and nothing secret) is passed at init time with -backend-config.
  # Credentials come from the OIDC-federated identity of the deploy workflow; none are stored here.
  backend "gcs" {
    prefix = "zaghlol/staging"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
