# modules/gcs-bucket/variables.tf
# Reusable private GCS bucket (e.g. for versioned application artifacts).

variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "name" {
  description = "Globally-unique bucket name."
  type        = string
}

variable "location" {
  description = "Bucket location (region like us-central1, or multi-region like US)."
  type        = string
}

variable "storage_class" {
  description = "Default storage class."
  type        = string
  default     = "STANDARD"
}

variable "enable_versioning" {
  description = "Keep noncurrent object versions (rollback-friendly artifact storage)."
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Allow Terraform to delete a non-empty bucket. Default true so `terraform destroy` is clean; set false to guard a bucket that must not be emptied."
  type        = bool
  default     = true
}

variable "uniform_bucket_level_access" {
  description = "Enforce uniform (IAM-only) access; disables per-object ACLs."
  type        = bool
  default     = true
}

variable "public_access_prevention" {
  description = "Block public access (enforced) or inherit org policy."
  type        = string
  default     = "enforced"
}

variable "viewers" {
  description = "IAM members granted roles/storage.objectViewer (e.g. the app service account)."
  type        = list(string)
  default     = []
}

variable "labels" {
  description = "Labels applied to the bucket."
  type        = map(string)
  default     = {}
}
