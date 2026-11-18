# Real-time developer notifications (RTDN) from Google Play (deployment section 3, T-133).

data "google_project" "this" {
  project_id = var.project_id
}

resource "google_pubsub_topic" "rtdn" {
  project = var.project_id
  name    = "zaghlol-rtdn-${var.environment}"

  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }
}

# Only Google Play's publisher account may publish.
resource "google_pubsub_topic_iam_member" "play_publisher" {
  project = var.project_id
  topic   = google_pubsub_topic.rtdn.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:google-play-developer-notifications@system.gserviceaccount.com"
}

# Push identity: has no roles of its own. Pub/Sub mints OIDC tokens as this account.
resource "google_service_account" "rtdn_push" {
  project      = var.project_id
  account_id   = "zaghlol-rtdn-push"
  display_name = "Zaghlol RTDN push (OIDC identity only)"
}

resource "google_service_account_iam_member" "pubsub_token_creator" {
  service_account_id = google_service_account.rtdn_push.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${data.google_project.this.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_pubsub_subscription" "rtdn_push" {
  project = var.project_id
  name    = "zaghlol-rtdn-push-${var.environment}"
  topic   = google_pubsub_topic.rtdn.id

  ack_deadline_seconds       = 30
  message_retention_duration = "604800s" # 7 days
  retain_acked_messages      = false

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  # No dead-letter topic: the voided-purchases job and the expiry sweep fill gaps (deployment section 3).

  push_config {
    push_endpoint = var.push_endpoint

    oidc_token {
      service_account_email = google_service_account.rtdn_push.email
      audience              = var.push_endpoint
    }
  }

  depends_on = [google_service_account_iam_member.pubsub_token_creator]
}
