# modules/github-oidc/main.tf
# Keyless GitHub Actions -> GCP auth via Workload Identity Federation (WIF).
#
# GitHub Actions presents a short-lived OIDC token; STS exchanges it for
# credentials that impersonate the EXISTING least-privilege CI service account
# (created by the cloud-build module). No service-account JSON key is ever
# created, stored, or rotated — satisfying the "no long-lived credentials" rule.

locals {
  # Pool/provider IDs must be 4-32 chars, lowercase, start with a letter.
  pool_id     = "${var.app_name}-${var.environment}-ghpool"
  provider_id = "${var.app_name}-${var.environment}-ghprov"

  # Impersonation principal.
  # - Default (github_ref==""): any branch of the repo — scoped on
  #   attribute.repository = "<owner>/<repo>" (a principalSet, many tokens).
  # - Branch-scoped (github_ref set): exactly one repo+ref. We scope on
  #   google.subject, whose value is "repo:<owner>/<repo>:ref:<ref>", so it
  #   pins BOTH repository and ref in a single principal. Scoping on
  #   attribute.ref alone would be unsafe — it omits the repo, so any repo from
  #   the same owner with a matching branch would qualify.
  impersonation_member = (
    var.github_ref == ""
    ? "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_owner}/${var.github_repo}"
    : "principal://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/subject/repo:${var.github_owner}/${var.github_repo}:ref:${var.github_ref}"
  )
}

# Pool that holds external (GitHub) identities for this environment.
resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = local.pool_id
  display_name              = "${var.app_name}-${var.environment} GitHub"
  description               = "GitHub Actions OIDC identities for ${var.environment} deploys."
}

# OIDC provider trusting GitHub's token issuer.
resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = local.provider_id
  display_name                       = "GitHub Actions"

  # Map the GitHub claims we use in IAM bindings/conditions.
  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.ref"              = "assertion.ref"
  }

  # Google rejects a provider without an attribute condition. Lock it to our
  # owner so tokens from unrelated repos can never use this provider (the
  # service-account binding below narrows it further to the exact repo).
  attribute_condition = "assertion.repository_owner == '${var.github_owner}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Allow this repository (optionally only a single ref) to impersonate the CI
# service account. See local.impersonation_member for the scoping rationale.
resource "google_service_account_iam_member" "wif_impersonate" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${var.service_account_email}"
  role               = "roles/iam.workloadIdentityUser"
  member             = local.impersonation_member
}
