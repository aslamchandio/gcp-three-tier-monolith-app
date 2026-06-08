# modules/health-check/main.tf

locals {
  name_prefix = "${var.app_name}-${var.environment}"
}

resource "google_compute_region_health_check" "http" {
  project = var.project_id
  region  = var.region
  name    = "${local.name_prefix}-${var.name_suffix}"

  check_interval_sec  = var.check_interval_sec
  timeout_sec         = var.timeout_sec
  healthy_threshold   = var.healthy_threshold
  unhealthy_threshold = var.unhealthy_threshold

  http_health_check {
    port         = var.app_port
    request_path = var.health_check_path
  }

  log_config {
    enable = true
  }
}
