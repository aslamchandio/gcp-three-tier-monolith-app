# modules/cloud-build/main.tf
#
# CI deploy identity (least privilege). GitHub Actions impersonates this service
# account via Workload Identity Federation (see modules/github-oidc) to publish
# the app artifact to GCS and roll the MIG — no JSON keys are ever created.

locals {
  name_prefix = "${var.app_name}-${var.environment}"
  ci_member   = "serviceAccount:${google_service_account.ci.email}"
}

# Dedicated, least-privilege CI identity (no JSON keys; impersonated via WIF).
resource "google_service_account" "ci" {
  project      = var.project_id
  account_id   = "${local.name_prefix}-ci-sa"
  display_name = "${local.name_prefix} CI deploy"
  description  = "Publishes the app artifact and rolls the MIG (impersonated by GitHub Actions via WIF)."
}

# Write artifacts to the bucket (bucket-scoped, not project-wide).
resource "google_storage_bucket_iam_member" "ci_object_admin" {
  bucket = var.artifact_bucket_name
  role   = "roles/storage.objectAdmin"
  member = local.ci_member
}

# Roll the MIG (rolling-action replace creates/deletes instances).
resource "google_project_iam_member" "ci_compute" {
  project = var.project_id
  role    = "roles/compute.instanceAdmin.v1"
  member  = local.ci_member
}

# instanceAdmin.v1 doesn't include "use" on the health check the MIG references
# for autohealing; rolling-action replace needs it. Grant only that permission.
resource "google_project_iam_custom_role" "ci_mig" {
  project     = var.project_id
  role_id     = replace("${local.name_prefix}_ci_mig", "-", "_")
  title       = "${local.name_prefix} CI MIG roll"
  description = "Extra permissions for Cloud Build to roll the MIG."
  permissions = ["compute.regionHealthChecks.use"]
}

resource "google_project_iam_member" "ci_mig" {
  project = var.project_id
  role    = google_project_iam_custom_role.ci_mig.id
  member  = local.ci_member
}

# Required so the build can write its own logs (user-specified SA).
resource "google_project_iam_member" "ci_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = local.ci_member
}

# Replacing instances that run as the app SA requires actAs on that SA.
resource "google_service_account_iam_member" "ci_act_as_app_sa" {
  service_account_id = var.app_service_account_id
  role               = "roles/iam.serviceAccountUser"
  member             = local.ci_member
}
