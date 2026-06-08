# modules/instance-template/outputs.tf

output "template_self_link" {
  description = "Self link of the instance template (pass to the MIG)."
  value       = google_compute_region_instance_template.app.self_link
}

output "template_id" {
  description = "Instance template resource ID."
  value       = google_compute_region_instance_template.app.id
}

output "template_name" {
  description = "Generated instance template name."
  value       = google_compute_region_instance_template.app.name
}
