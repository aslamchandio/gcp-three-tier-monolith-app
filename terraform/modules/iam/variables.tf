# modules/iam/variables.tf
# Service account + least-privilege project roles for the application tier.

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

variable "account_id" {
  description = "Optional explicit service account ID. If empty, derived as <app_name>-<environment>-app-sa (must be 6-30 chars)."
  type        = string
  default     = ""

  validation {
    condition     = var.account_id == "" || can(regex("^[a-z][a-z0-9-]{5,29}$", var.account_id))
    error_message = "account_id must be 6-30 chars, lowercase letters/digits/hyphens, starting with a letter."
  }
}

variable "display_name" {
  description = "Optional human-readable display name for the service account."
  type        = string
  default     = ""
}

variable "project_roles" {
  description = "Least-privilege project-level roles granted to the service account. Avoid roles/owner and roles/editor."
  type        = list(string)
  default = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudsql.client",
  ]

  validation {
    condition     = !contains(var.project_roles, "roles/owner") && !contains(var.project_roles, "roles/editor")
    error_message = "Broad roles (owner/editor) are not allowed; grant specific least-privilege roles."
  }
}
