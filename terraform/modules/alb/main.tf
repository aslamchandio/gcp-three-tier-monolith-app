# modules/alb/main.tf
# Regional external Application Load Balancer.
#
#   client -> external IP -> forwarding rule(:80/:443) -> target proxy
#          -> URL map -> regional backend service -> MIG (app :8080)
#
# HTTP always exists. When enable_https = true, :443 serves the app and :80
# redirects to HTTPS.

locals {
  name_prefix   = "${var.app_name}-${var.environment}"
  https_enabled = var.enable_https

  # A Google-managed cert (Certificate Manager) is used when domains are given;
  # otherwise HTTPS falls back to a self-managed cert from ssl_certificate/key.
  use_managed_cert = length(var.managed_cert_domains) > 0
  use_self_signed  = local.https_enabled && !local.use_managed_cert
}

# --- Proxy-only subnet (shared by all regional Envoy-based LBs in the region) -
resource "google_compute_subnetwork" "proxy" {
  count = var.create_proxy_subnet ? 1 : 0

  project       = var.project_id
  region        = var.region
  name          = "${local.name_prefix}-proxy-subnet"
  network       = var.vpc_self_link
  ip_cidr_range = var.proxy_subnet_cidr
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
}

# --- Firewall: allow the proxy-only subnet to reach the backends --------------
# A regional Envoy-based ALB sends DATA-PLANE traffic from the proxy-only subnet
# (not from the Google health-check ranges). Without this rule the explicit
# deny-all drops those requests and clients see "upstream request timeout" even
# though the backends report HEALTHY (health checks use a different source range).
resource "google_compute_firewall" "allow_proxy_to_backends" {
  count = length(var.backend_network_tags) > 0 ? 1 : 0

  project     = var.project_id
  name        = "${local.name_prefix}-allow-proxy-to-app"
  description = "Allow the regional ALB proxy-only subnet to reach the application port on backend instances."
  network     = var.vpc_self_link
  direction   = "INGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
    ports    = [tostring(var.app_port)]
  }

  source_ranges = [var.proxy_subnet_cidr]
  target_tags   = var.backend_network_tags
}

# --- External regional IP -----------------------------------------------------
resource "google_compute_address" "lb" {
  project      = var.project_id
  region       = var.region
  name         = "${local.name_prefix}-lb-ip"
  address_type = "EXTERNAL"
  network_tier = var.network_tier
}

# --- Backend service (MIG attached, logging enabled) -------------------------
resource "google_compute_region_backend_service" "app" {
  project               = var.project_id
  region                = var.region
  name                  = "${local.name_prefix}-backend"
  protocol              = "HTTP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_name             = var.named_port_name
  timeout_sec           = var.backend_timeout_sec
  health_checks         = [var.health_check_self_link]

  backend {
    group           = var.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }

  # Ensure the proxy subnet exists before the LB data path is wired up.
  depends_on = [google_compute_subnetwork.proxy]
}

# --- URL maps -----------------------------------------------------------------
# HTTP url map: routes to backend, or (when HTTPS enabled) 301-redirects to HTTPS.
resource "google_compute_region_url_map" "http" {
  project = var.project_id
  region  = var.region
  name    = "${local.name_prefix}-http-urlmap"

  default_service = local.https_enabled ? null : google_compute_region_backend_service.app.id

  dynamic "default_url_redirect" {
    for_each = local.https_enabled ? [1] : []
    content {
      https_redirect         = true
      redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
      strip_query            = false
    }
  }
}

# HTTPS url map: routes to the backend service.
resource "google_compute_region_url_map" "https" {
  count = local.https_enabled ? 1 : 0

  project         = var.project_id
  region          = var.region
  name            = "${local.name_prefix}-https-urlmap"
  default_service = google_compute_region_backend_service.app.id
}

# --- Target proxies -----------------------------------------------------------
resource "google_compute_region_target_http_proxy" "http" {
  project = var.project_id
  region  = var.region
  name    = "${local.name_prefix}-http-proxy"
  url_map = google_compute_region_url_map.http.id
}

# --- Google-managed certificate (Certificate Manager, DNS authorization) ------
# One DNS authorization per domain proves control; create the CNAME it emits
# (managed_cert_dns_records output) at your DNS provider. These are created
# whenever domains are supplied — independent of enable_https — so the cert can
# reach ACTIVE before the HTTPS listener is switched on.
resource "google_certificate_manager_dns_authorization" "app" {
  for_each = toset(var.managed_cert_domains)

  project  = var.project_id
  location = var.region
  name     = "${local.name_prefix}-${replace(each.value, ".", "-")}-dnsauth"
  domain   = each.value
}

resource "google_certificate_manager_certificate" "managed" {
  count = local.use_managed_cert ? 1 : 0

  project  = var.project_id
  location = var.region
  name     = "${local.name_prefix}-managed-cert"

  managed {
    domains            = var.managed_cert_domains
    dns_authorizations = [for d in var.managed_cert_domains : google_certificate_manager_dns_authorization.app[d].id]
  }
}

# --- Self-managed certificate (used only when no managed domains are given) ----
resource "google_compute_region_ssl_certificate" "app" {
  count = local.use_self_signed ? 1 : 0

  project     = var.project_id
  region      = var.region
  name        = "${local.name_prefix}-cert"
  certificate = var.ssl_certificate
  private_key = var.ssl_private_key

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = var.ssl_certificate != "" && var.ssl_private_key != ""
      error_message = "ssl_certificate and ssl_private_key are required when enable_https = true and managed_cert_domains is empty."
    }
  }
}

resource "google_compute_region_target_https_proxy" "https" {
  count = local.https_enabled ? 1 : 0

  project = var.project_id
  region  = var.region
  name    = "${local.name_prefix}-https-proxy"
  url_map = google_compute_region_url_map.https[0].id

  # Attach the managed cert when domains are set, else the self-managed one.
  certificate_manager_certificates = local.use_managed_cert ? [google_certificate_manager_certificate.managed[0].id] : null
  ssl_certificates                 = local.use_self_signed ? [google_compute_region_ssl_certificate.app[0].id] : null
}

# --- Forwarding rules ---------------------------------------------------------
resource "google_compute_forwarding_rule" "http" {
  project               = var.project_id
  region                = var.region
  name                  = "${local.name_prefix}-http-fr"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_protocol           = "TCP"
  port_range            = "80"
  target                = google_compute_region_target_http_proxy.http.id
  ip_address            = google_compute_address.lb.id
  network_tier          = var.network_tier

  # Required for a regional ALB so GCP resolves the proxy-only subnet in this VPC.
  network = var.vpc_self_link

  depends_on = [google_compute_subnetwork.proxy]
}

resource "google_compute_forwarding_rule" "https" {
  count = local.https_enabled ? 1 : 0

  project               = var.project_id
  region                = var.region
  name                  = "${local.name_prefix}-https-fr"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_protocol           = "TCP"
  port_range            = "443"
  target                = google_compute_region_target_https_proxy.https[0].id
  ip_address            = google_compute_address.lb.id
  network_tier          = var.network_tier

  # Required for a regional ALB so GCP resolves the proxy-only subnet in this VPC.
  network = var.vpc_self_link

  depends_on = [google_compute_subnetwork.proxy]
}
