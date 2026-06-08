# modules/secret-manager/outputs.tf

output "secret_ids" {
  description = "Map of logical key => created secret_id."
  value       = { for k, s in google_secret_manager_secret.this : k => s.secret_id }
}

output "secret_names" {
  description = "Map of logical key => fully-qualified secret resource name."
  value       = { for k, s in google_secret_manager_secret.this : k => s.name }
}
