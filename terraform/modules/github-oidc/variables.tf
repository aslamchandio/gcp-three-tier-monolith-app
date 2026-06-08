# modules/github-oidc/variables.tf
# Keyless CI/CD auth for GitHub Actions via Workload Identity Federation.
# This module is only instantiated when WIF is enabled, so owner/repo are
# required (no empty-string defaults).

variable "project_id" {
  description = "GCP project ID that hosts the workload identity pool."
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

variable "github_owner" {
  description = "GitHub repository owner/org allowed to mint tokens (e.g. aslamchandio)."
  type        = string

  validation {
    condition     = var.github_owner != ""
    error_message = "github_owner must be set when GitHub OIDC is enabled."
  }
}

variable "github_repo" {
  description = "GitHub repository name allowed to impersonate the CI service account."
  type        = string

  validation {
    condition     = var.github_repo != ""
    error_message = "github_repo must be set when GitHub OIDC is enabled."
  }
}

variable "service_account_email" {
  description = "Existing least-privilege CI service account (from the cloud-build module) that GitHub Actions impersonates. No JSON key is ever created."
  type        = string
}

variable "github_ref" {
  description = "Optional git ref to lock impersonation to (e.g. 'refs/heads/main'). When set, ONLY runs on that branch/tag can impersonate the CI service account; the OIDC token's attribute.ref must match. Leave empty (default) to allow any branch in the repo — fine for low-blast-radius envs like dev. Recommended 'refs/heads/main' for prod."
  type        = string
  default     = ""
}
