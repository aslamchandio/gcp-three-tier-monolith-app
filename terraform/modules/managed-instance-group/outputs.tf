# modules/managed-instance-group/outputs.tf

output "instance_group" {
  description = "Self link of the MIG's instance group (attach to the backend service)."
  value       = google_compute_region_instance_group_manager.app.instance_group
}

output "mig_name" {
  description = "Name of the Managed Instance Group."
  value       = google_compute_region_instance_group_manager.app.name
}

output "mig_self_link" {
  description = "Self link of the Managed Instance Group manager."
  value       = google_compute_region_instance_group_manager.app.self_link
}

output "autoscaler_name" {
  description = "Name of the regional autoscaler (null when autoscaling is disabled)."
  value       = var.enable_autoscaling ? google_compute_region_autoscaler.app[0].name : null
}
