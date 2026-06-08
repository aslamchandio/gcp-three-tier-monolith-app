# modules/cloud-sql/outputs.tf

output "instance_name" {
  description = "Name of the Cloud SQL instance."
  value       = google_sql_database_instance.postgres.name
}

output "instance_connection_name" {
  description = "Instance connection name (project:region:instance) for the Cloud SQL Auth Proxy."
  value       = google_sql_database_instance.postgres.connection_name
}

output "private_ip_address" {
  description = "Private IP address of the Cloud SQL instance (reachable only inside the VPC)."
  value       = google_sql_database_instance.postgres.private_ip_address
}

output "database_name" {
  description = "Name of the application database."
  value       = google_sql_database.app.name
}

output "database_user" {
  description = "Name of the application database user."
  value       = google_sql_user.app.name
}

output "password_secret_id" {
  description = "Secret Manager secret ID holding the DB password (grant the app SA secretAccessor on this)."
  value       = google_secret_manager_secret.db_password.secret_id
}

output "password_secret_name" {
  description = "Fully-qualified Secret Manager secret resource name."
  value       = google_secret_manager_secret.db_password.name
}

output "db_password" {
  description = "The application user's password (sensitive). Prefer reading from Secret Manager at runtime."
  value       = local.db_password
  sensitive   = true
}
