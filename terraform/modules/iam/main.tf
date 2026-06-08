# modules/iam/main.tf
# Creates a dedicated service account for the application instances and grants
# only the specific project roles they need (least privilege). Secret access is
# granted at the secret level by the secret-manager module, not here.

locals {
  name_prefix = "${var.app_name}-${var.environment}"
  account_id  = var.account_id != "" ? var.account_id : "${local.name_prefix}-app-sa"
}

resource "google_service_account" "app" {
  project      = var.project_id
  account_id   = local.account_id
  display_name = var.display_name != "" ? var.display_name : "${local.name_prefix} application service account"
  description  = "Runtime identity for ${local.name_prefix} Compute Engine application instances."
}

# Additive role bindings (google_project_iam_member) so we never clobber other
# members on these roles.
resource "google_project_iam_member" "roles" {
  for_each = toset(var.project_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.app.email}"
}
