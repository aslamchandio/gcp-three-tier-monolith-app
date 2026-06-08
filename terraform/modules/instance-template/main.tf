# modules/instance-template/main.tf
# Immutable instance template for the application MIG. Uses name_prefix +
# create_before_destroy so a template change rolls out as a new template without
# a destroy gap (required for MIG rolling updates).

locals {
  name_prefix = "${var.app_name}-${var.environment}"

  # The startup script is supplied as metadata under the conventional key.
  metadata = merge(
    var.startup_script != "" ? { "startup-script" = var.startup_script } : {},
    var.metadata,
  )
}

resource "google_compute_region_instance_template" "app" {
  project      = var.project_id
  region       = var.region
  name_prefix  = "${local.name_prefix}-tmpl-"
  description  = "Application instance template for ${local.name_prefix}."
  machine_type = var.machine_type
  tags         = var.network_tags
  labels       = var.labels

  # Boot disk
  disk {
    source_image = var.source_image
    auto_delete  = true
    boot         = true
    disk_size_gb = var.disk_size_gb
    disk_type    = var.disk_type
  }

  # No access_config block => NO external IP. Outbound goes through Cloud NAT.
  network_interface {
    network    = var.network
    subnetwork = var.subnetwork
  }

  service_account {
    email  = var.service_account_email
    scopes = var.service_account_scopes
  }

  dynamic "shielded_instance_config" {
    for_each = var.enable_shielded_vm ? [1] : []
    content {
      enable_secure_boot          = true
      enable_vtpm                 = true
      enable_integrity_monitoring = true
    }
  }

  metadata = local.metadata

  lifecycle {
    create_before_destroy = true
  }
}
