output "topic_name" {
  description = "Paste into Play Console > Monetization setup > Real-time developer notifications (projects/<project>/topics/<name>)."
  value       = google_pubsub_topic.rtdn.id
}

output "subscription_id" {
  description = "Rtdn:Subscription."
  value       = google_pubsub_subscription.rtdn_push.id
}

output "push_service_account" {
  description = "Rtdn:PushServiceAccount."
  value       = google_service_account.rtdn_push.email
}

output "audience" {
  description = "Rtdn:Audience."
  value       = var.push_endpoint
}
