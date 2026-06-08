# modules/network/main.tf
# Reusable, environment-agnostic network building block:
# VPC, application subnet, Private Services Access, Cloud Router, Cloud NAT.

locals {
  # Naming: <app_name>-<environment>-<resource>
  name_prefix = "${var.app_name}-${var.environment}"

  network_name = var.network_name != "" ? var.network_name : "${local.name_prefix}-vpc"

  # Network tag applied to future application instances; firewall rules target it.
  app_network_tag = var.app_network_tag != "" ? var.app_network_tag : "${local.name_prefix}-app"
}

# --- Custom VPC ---------------------------------------------------------------
# Custom-mode: subnets are created explicitly, never auto-generated. The default
# VPC is never used.
resource "google_compute_network" "vpc" {
  name                    = local.network_name
  description             = "Custom VPC for the ${local.name_prefix} three-tier application."
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  project                 = var.project_id

  # delete_default_routes_on_create stays false: the default route to the
  # internet gateway is required for Cloud NAT egress to function.
}

# --- Application subnet --------------------------------------------------------
# Private Google Access lets no-external-IP instances reach Google APIs;
# VPC Flow Logs provide network observability.
resource "google_compute_subnetwork" "app" {
  name          = "${local.name_prefix}-app-subnet"
  description   = "Application tier subnet for ${local.name_prefix} backend instances."
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.app_subnet_cidr

  private_ip_google_access = true

  dynamic "log_config" {
    for_each = var.enable_flow_logs ? [1] : []
    content {
      aggregation_interval = "INTERVAL_5_SEC"
      flow_sampling        = 0.5
      metadata             = "INCLUDE_ALL_METADATA"
    }
  }
}

# --- Private Services Access (PSA) --------------------------------------------
# Reserves an internal range and peers the VPC with Google's service producer
# network — prerequisite for Cloud SQL PRIVATE IP in a later phase.
resource "google_compute_global_address" "psa_range" {
  name         = "${local.name_prefix}-psa-range"
  description  = "Private Services Access range reserved for Cloud SQL private IP."
  project      = var.project_id
  network      = google_compute_network.vpc.id
  purpose      = "VPC_PEERING"
  address_type = "INTERNAL"

  # Explicit start address when provided; otherwise GCP auto-allocates a block.
  address       = var.psa_address != "" ? var.psa_address : null
  prefix_length = var.psa_prefix_length
}

resource "google_service_networking_connection" "psa" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa_range.name]

  # Clean teardown: release the peering on destroy so the VPC can be deleted.
  deletion_policy = "ABANDON"
}

# --- Cloud Router + Cloud NAT -------------------------------------------------
# Outbound internet for instances with NO external IP (package updates, etc.).
resource "google_compute_router" "router" {
  name        = "${local.name_prefix}-router"
  description = "Cloud Router for ${local.name_prefix} NAT."
  project     = var.project_id
  region      = var.region
  network     = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name    = "${local.name_prefix}-nat"
  project = var.project_id
  region  = var.region
  router  = google_compute_router.router.name

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = var.nat_log_filter
  }
}
