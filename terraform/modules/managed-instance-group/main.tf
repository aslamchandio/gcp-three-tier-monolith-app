# modules/managed-instance-group/main.tf

locals {
  name_prefix = "${var.app_name}-${var.environment}"
}

resource "google_compute_region_instance_group_manager" "app" {
  project            = var.project_id
  region             = var.region
  name               = "${local.name_prefix}-mig"
  base_instance_name = "${local.name_prefix}-app"

  version {
    instance_template = var.instance_template
  }

  # When autoscaling is enabled the autoscaler owns the size, so leave target_size
  # unset (null) and ignore drift on it. Otherwise pin it to instance_count.
  target_size = var.enable_autoscaling ? null : var.instance_count

  # Named port the regional backend service maps to (port 8080).
  named_port {
    name = var.named_port_name
    port = var.app_port
  }

  # Recreate unhealthy instances automatically. initial_delay_sec gives the
  # startup script + app time to come up before probing.
  auto_healing_policies {
    health_check      = var.health_check_self_link
    initial_delay_sec = var.auto_healing_initial_delay_sec
  }

  # Proactive rolling updates: surge new instances, replace old ones, no downtime.
  update_policy {
    type                         = "PROACTIVE"
    minimal_action               = "REPLACE"
    replacement_method           = "SUBSTITUTE"
    instance_redistribution_type = "PROACTIVE"
    max_surge_fixed              = var.max_surge_fixed
    max_unavailable_fixed        = var.max_unavailable_fixed
  }

  # Empty list => let GCP spread across all zones in the region.
  distribution_policy_zones = length(var.distribution_zones) > 0 ? var.distribution_zones : null

  lifecycle {
    # When the autoscaler is attached it manages target_size; ignore drift so
    # Terraform and the autoscaler do not fight over the instance count.
    ignore_changes = [target_size]
  }
}

# --- Autoscaler (optional) ----------------------------------------------------
# Regional autoscaler driven by average CPU utilization, with a conservative
# scale-in control so the group does not shrink too aggressively after a spike.
resource "google_compute_region_autoscaler" "app" {
  count = var.enable_autoscaling ? 1 : 0

  project = var.project_id
  region  = var.region
  name    = "${local.name_prefix}-autoscaler"
  target  = google_compute_region_instance_group_manager.app.id

  autoscaling_policy {
    min_replicas    = var.min_replicas
    max_replicas    = var.max_replicas
    cooldown_period = var.autoscaling_cooldown_sec

    cpu_utilization {
      target = var.autoscaling_cpu_target
    }

    scale_in_control {
      time_window_sec = var.scale_in_window_sec
      max_scaled_in_replicas {
        fixed = var.scale_in_max_replicas
      }
    }
  }
}
