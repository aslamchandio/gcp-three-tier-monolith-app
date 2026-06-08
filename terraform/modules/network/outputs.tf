# modules/network/outputs.tf

output "vpc_name" {
  description = "Name of the custom VPC."
  value       = google_compute_network.vpc.name
}

output "vpc_self_link" {
  description = "Self link of the custom VPC."
  value       = google_compute_network.vpc.self_link
}

output "app_subnet_name" {
  description = "Name of the application subnet."
  value       = google_compute_subnetwork.app.name
}

output "app_subnet_self_link" {
  description = "Self link of the application subnet."
  value       = google_compute_subnetwork.app.self_link
}

output "app_subnet_cidr" {
  description = "Primary CIDR range of the application subnet."
  value       = google_compute_subnetwork.app.ip_cidr_range
}

output "app_network_tag" {
  description = "Network tag to attach to future application instances so firewall rules apply."
  value       = local.app_network_tag
}

output "psa_range_name" {
  description = "Name of the reserved Private Services Access range for Cloud SQL private IP."
  value       = google_compute_global_address.psa_range.name
}

output "psa_range_address" {
  description = "Reserved PSA IP range (CIDR) for Cloud SQL private IP."
  value       = "${google_compute_global_address.psa_range.address}/${google_compute_global_address.psa_range.prefix_length}"
}

output "service_networking_connection" {
  description = "Service Networking peering connection ID for Cloud SQL private connectivity."
  value       = google_service_networking_connection.psa.id
}

output "cloud_router_name" {
  description = "Name of the Cloud Router backing Cloud NAT."
  value       = google_compute_router.router.name
}

output "cloud_nat_name" {
  description = "Name of the Cloud NAT gateway for private-instance outbound access."
  value       = google_compute_router_nat.nat.name
}
