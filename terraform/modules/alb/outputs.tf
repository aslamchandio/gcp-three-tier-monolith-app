# modules/alb/outputs.tf

output "load_balancer_ip" {
  description = "External IP address of the load balancer."
  value       = google_compute_address.lb.address
}

output "http_url" {
  description = "HTTP URL of the load balancer."
  value       = "http://${google_compute_address.lb.address}"
}

output "https_url" {
  description = "HTTPS URL (null when HTTPS is disabled). Uses the first managed domain when a Google-managed cert is configured, else the LB IP."
  value       = local.https_enabled ? "https://${local.use_managed_cert ? var.managed_cert_domains[0] : google_compute_address.lb.address}" : null
}

output "managed_cert_dns_records" {
  description = "Per-domain DNS records to create for Certificate Manager DNS authorization (a CNAME that proves domain control). Add these at your DNS provider; the managed cert reaches ACTIVE once they validate. Empty when no managed domains are configured."
  value = {
    for domain, auth in google_certificate_manager_dns_authorization.app :
    domain => one(auth.dns_resource_record)
  }
}

output "managed_cert_id" {
  description = "Resource ID of the Google-managed certificate (null when not configured)."
  value       = local.use_managed_cert ? google_certificate_manager_certificate.managed[0].id : null
}

output "backend_service_name" {
  description = "Name of the regional backend service."
  value       = google_compute_region_backend_service.app.name
}

output "backend_service_id" {
  description = "ID of the regional backend service."
  value       = google_compute_region_backend_service.app.id
}

output "proxy_subnet_self_link" {
  description = "Self link of the proxy-only subnet (null if not created here)."
  value       = var.create_proxy_subnet ? google_compute_subnetwork.proxy[0].self_link : null
}
