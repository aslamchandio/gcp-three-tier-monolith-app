# modules/iam/outputs.tf

output "service_account_email" {
  description = "Email of the application service account."
  value       = google_service_account.app.email
}

output "service_account_id" {
  description = "Fully-qualified service account resource ID."
  value       = google_service_account.app.id
}

output "service_account_member" {
  description = "IAM member string (serviceAccount:<email>) for granting further access."
  value       = "serviceAccount:${google_service_account.app.email}"
}

output "service_account_name" {
  description = "Service account unique name."
  value       = google_service_account.app.name
}
