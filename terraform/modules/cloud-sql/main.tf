# modules/cloud-sql/main.tf
# Private-IP-only Cloud SQL for PostgreSQL.
# - No public IP (ipv4_enabled = false); reachable only over the VPC private path.
# - Password is generated (or supplied) and stored in Secret Manager — never
#   hardcoded. The app reads it from Secret Manager via IAM at runtime.

locals {
  name_prefix = "${var.app_name}-${var.environment}"

  # Use a supplied password if given, otherwise the generated one.
  db_password = var.db_password != "" ? var.db_password : random_password.db[0].result
}

# Generate a strong password only when one is not supplied.
resource "random_password" "db" {
  count            = var.db_password == "" ? 1 : 0
  length           = 24
  special          = true
  override_special = "!#%*()-_=+[]{}<>:?"
}

# --- Cloud SQL instance (private IP only) -------------------------------------
resource "google_sql_database_instance" "postgres" {
  name             = "${local.name_prefix}-pg"
  project          = var.project_id
  region           = var.region
  database_version = var.database_version

  # Terraform-level guard against accidental destroy (mirrors the GCP setting).
  deletion_protection = var.enable_deletion_protection

  settings {
    tier              = var.tier
    availability_type = var.availability_type
    disk_size         = var.disk_size
    disk_type         = var.disk_type
    disk_autoresize   = var.disk_autoresize
    user_labels       = var.labels

    # GCP-level deletion protection.
    deletion_protection_enabled = var.enable_deletion_protection

    # Private IP only — no public IPv4, traffic stays on the VPC private path.
    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = var.network_id
      enable_private_path_for_google_cloud_services = true
      ssl_mode                                      = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = var.backup_enabled
      start_time                     = var.backup_start_time
      point_in_time_recovery_enabled = var.point_in_time_recovery_enabled
      transaction_log_retention_days = var.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = var.backup_retention_count
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.maintenance_window_day
      hour         = var.maintenance_window_hour
      update_track = "stable"
    }

    dynamic "database_flags" {
      for_each = var.database_flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }

  # The private IP cannot be provisioned until the Service Networking peering
  # (Private Services Access) is established. The root passes that dependency
  # via the module's depends_on.
}

# --- Application database ------------------------------------------------------
resource "google_sql_database" "app" {
  name     = var.db_name
  project  = var.project_id
  instance = google_sql_database_instance.postgres.name
}

# --- Application database user -------------------------------------------------
resource "google_sql_user" "app" {
  name     = var.db_user
  project  = var.project_id
  instance = google_sql_database_instance.postgres.name
  password = local.db_password

  # On destroy, abandon (don't DROP) the user. A PostgreSQL role that owns
  # objects cannot be dropped via the API, which otherwise fails `terraform
  # destroy`; the user is removed anyway when the instance is deleted. This
  # makes teardown clean with no manual `state rm`.
  deletion_policy = "ABANDON"
}

# --- Secret Manager: store the DB password for the app to consume -------------
resource "google_secret_manager_secret" "db_password" {
  project   = var.project_id
  secret_id = "${local.name_prefix}-db-password"
  labels    = var.labels

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = local.db_password
}
