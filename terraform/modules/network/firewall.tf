# modules/network/firewall.tf
# Least-privilege firewall. GCP implicitly denies all ingress (priority 65535);
# we add an explicit, logged deny baseline and open only required paths. Rules
# are scoped by the application network tag (local.app_network_tag).

# --- Baseline: explicit deny-all ingress (logged) -----------------------------
resource "google_compute_firewall" "deny_all_ingress" {
  name        = "${local.name_prefix}-deny-all-ingress"
  description = "Explicit deny-by-default for all ingress (logged). Allow rules below override by priority."
  project     = var.project_id
  network     = google_compute_network.vpc.name
  direction   = "INGRESS"
  priority    = 65534

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# --- Base rule: internal east-west communication within the VPC ---------------
resource "google_compute_firewall" "allow_internal" {
  name        = "${local.name_prefix}-allow-internal"
  description = "Allow internal traffic between resources inside the application subnet."
  project     = var.project_id
  network     = google_compute_network.vpc.name
  direction   = "INGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = [var.app_subnet_cidr]
  target_tags   = [local.app_network_tag]
}

# --- IAP SSH: administrative SSH only via Identity-Aware Proxy ----------------
# No 0.0.0.0/0 SSH. Source restricted to Google's IAP TCP forwarding range.
resource "google_compute_firewall" "allow_iap_ssh" {
  name        = "${local.name_prefix}-allow-iap-ssh"
  description = "Allow SSH (tcp/22) only from the Google IAP TCP forwarding range."
  project     = var.project_id
  network     = google_compute_network.vpc.name
  direction   = "INGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = [var.iap_source_range]
  target_tags   = [local.app_network_tag]
}

# --- Health checks: Application Load Balancer probes --------------------------
# Google LB health checkers and the GFE proxy share these source ranges.
resource "google_compute_firewall" "allow_health_check" {
  name        = "${local.name_prefix}-allow-health-check"
  description = "Allow Google load balancer health check and proxy ranges to reach the application port."
  project     = var.project_id
  network     = google_compute_network.vpc.name
  direction   = "INGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
    ports    = [tostring(var.app_port)]
  }

  source_ranges = var.health_check_source_ranges
  target_tags   = [local.app_network_tag]
}

# NOTE: a dedicated "allow app port from the subnet" rule used to live here but
# was removed as redundant — `allow_internal` above already permits ALL TCP from
# var.app_subnet_cidr to the app tag, so the app port is a strict subset. The
# proxy-only subnet and health-check ranges reach the app port via their own
# rules (in the alb module and allow_health_check, respectively).
