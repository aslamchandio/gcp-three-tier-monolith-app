# modules/github-oidc/outputs.tf

output "workload_identity_provider" {
  description = "Full resource name of the WIF provider. Set this as the GitHub environment variable WIF_PROVIDER for google-github-actions/auth."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "pool_name" {
  description = "Full resource name of the workload identity pool."
  value       = google_iam_workload_identity_pool.github.name
}

output "deploy_service_account" {
  description = "Service account GitHub Actions impersonates. Set as the GitHub environment variable DEPLOY_SA."
  value       = var.service_account_email
}
