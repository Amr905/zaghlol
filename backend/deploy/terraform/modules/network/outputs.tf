output "network_id" {
  value = google_compute_network.this.id
}

output "network_name" {
  value = google_compute_network.this.name
}

output "subnet_name" {
  value = google_compute_subnetwork.run.name
}

output "private_services_network" {
  description = "VPC id, returned from the peering resource so that dependants wait for the connection."
  value       = google_service_networking_connection.private_services.network
}
