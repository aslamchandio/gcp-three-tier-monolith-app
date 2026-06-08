# modules/secret-manager/variables.tf
# Reusable Secret Manager module:
#  - create secrets (optionally with an initial value), and/or
#  - grant secretAccessor to principals, on both created and pre-existing secrets.
#
# Secret VALUES must never be hardcoded in tfvars/code — pass them from a
# sensitive variable or generate them (e.g. random_password) in the root.

variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "labels" {
  description = "Labels applied to created secrets."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = <<-EOT
    Map of secrets to create. Key = secret_id. For each:
      secret_data : optional initial value (sensitive). Omit to create the
                    secret container without a version.
      accessors   : list of IAM members granted roles/secretmanager.secretAccessor.
  EOT
  type = map(object({
    secret_data = optional(string)
    accessors   = optional(list(string), [])
  }))
  default = {}
  # Not marked sensitive at the variable level because the map KEYS (secret ids)
  # drive for_each and must remain non-sensitive. The secret VALUE is masked
  # explicitly via sensitive() where it is written (see main.tf), and the
  # provider already treats secret_version.secret_data as sensitive.
}

variable "external_accessors" {
  description = "Grant secretAccessor on secrets that already exist (not created here). Map of existing secret_id => list of members."
  type        = map(list(string))
  default     = {}
}
