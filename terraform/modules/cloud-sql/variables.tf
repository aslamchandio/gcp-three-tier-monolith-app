# modules/cloud-sql/variables.tf
# Environment-agnostic inputs. Private-IP-only Cloud SQL for PostgreSQL.

variable "project_id" {
  description = "GCP project ID where Cloud SQL is created."
  type        = string
}

variable "region" {
  description = "GCP region for the Cloud SQL instance."
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

variable "network_id" {
  description = "Self link / ID of the VPC used for the private IP (e.g. module.network.vpc_self_link). Required for private connectivity."
  type        = string
}

variable "database_version" {
  description = "Cloud SQL PostgreSQL engine version."
  type        = string
  default     = "POSTGRES_15"

  validation {
    condition     = can(regex("^POSTGRES_", var.database_version))
    error_message = "This module is for PostgreSQL only (database_version must start with POSTGRES_)."
  }
}

variable "tier" {
  description = "Cloud SQL machine tier (e.g. db-custom-1-3840, db-custom-2-7680)."
  type        = string
  default     = "db-custom-1-3840"
}

variable "availability_type" {
  description = "ZONAL (single zone) or REGIONAL (HA, recommended for prod)."
  type        = string
  default     = "ZONAL"

  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "availability_type must be ZONAL or REGIONAL."
  }
}

variable "disk_size" {
  description = "Data disk size in GB."
  type        = number
  default     = 20
}

variable "disk_type" {
  description = "Data disk type: PD_SSD or PD_HDD."
  type        = string
  default     = "PD_SSD"
}

variable "disk_autoresize" {
  description = "Automatically grow the disk when near full."
  type        = bool
  default     = true
}

variable "db_name" {
  description = "Name of the application database to create."
  type        = string
  default     = "appdb"
}

variable "db_user" {
  description = "Application database user to create."
  type        = string
  default     = "appuser"
}

variable "db_password" {
  description = "Optional password for the application user. If empty, a strong random password is generated. Stored in Secret Manager, never hardcoded."
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_deletion_protection" {
  description = "Protect the instance from deletion (Terraform and GCP level). Default false so `terraform destroy` is clean; set true to guard a long-lived instance."
  type        = bool
  default     = false
}

variable "backup_enabled" {
  description = "Enable automated backups."
  type        = bool
  default     = true
}

variable "backup_start_time" {
  description = "Daily backup start time (UTC, HH:MM)."
  type        = string
  default     = "03:00"
}

variable "backup_retention_count" {
  description = "Number of automated backups to retain."
  type        = number
  default     = 7
}

variable "point_in_time_recovery_enabled" {
  description = "Enable point-in-time recovery (WAL archiving). Recommended for prod."
  type        = bool
  default     = true
}

variable "transaction_log_retention_days" {
  description = "Days of transaction logs retained for point-in-time recovery (1-7)."
  type        = number
  default     = 7
}

variable "maintenance_window_day" {
  description = "Maintenance window day of week (1=Monday ... 7=Sunday)."
  type        = number
  default     = 7
}

variable "maintenance_window_hour" {
  description = "Maintenance window start hour (0-23, UTC)."
  type        = number
  default     = 4
}

variable "database_flags" {
  description = "Optional map of PostgreSQL database flags (name => value)."
  type        = map(string)
  default     = {}
}

variable "labels" {
  description = "Labels applied to the instance and the Secret Manager secret."
  type        = map(string)
  default     = {}
}
