output "instance_name" {
  value = google_sql_database_instance.this.name
}

output "connection_name" {
  value = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Host= part of the connection strings (Npgsql, SSL Mode=Require)."
  value       = google_sql_database_instance.this.private_ip_address
}
