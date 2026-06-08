# modules/cloud-build/variables.tf
# CI deploy identity: a dedicated, least-privilege service account that GitHub
# Actions impersonates (via WIF) to publish the app artifact and roll the MIG.

variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "app_name" {
  description = "Application/project short name; part of the naming prefix."
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev/stage/prod); part of the naming prefix."
  type        = string
}

variable "artifact_bucket_name" {
  description = "Name of the GCS artifact bucket the CI identity may write to."
  type        = string
}

variable "app_service_account_id" {
  description = "Resource ID of the application service account (projects/.../serviceAccounts/...). The CI SA needs serviceAccountUser on it to roll instances that run as it."
  type        = string
}
