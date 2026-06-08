# modules/cloud-build/outputs.tf

output "ci_service_account_email" {
  description = "Email of the CI deploy service account (impersonated by GitHub Actions via WIF)."
  value       = google_service_account.ci.email
}
