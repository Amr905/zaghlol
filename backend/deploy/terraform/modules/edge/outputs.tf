output "load_balancer_ip" {
  description = "Point the A record of the hostname here. The managed certificate becomes ACTIVE after DNS resolves."
  value       = google_compute_global_address.this.address
}

output "assets_bucket" {
  value = google_storage_bucket.assets.name
}
