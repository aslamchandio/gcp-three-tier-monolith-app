# modules/health-check/outputs.tf

output "health_check_id" {
  description = "Regional health check resource ID."
  value       = google_compute_region_health_check.http.id
}

output "health_check_self_link" {
  description = "Self link (consumed by the backend service and MIG autohealing)."
  value       = google_compute_region_health_check.http.self_link
}
