# environments/dev/outputs.tf
# Full-stack outputs (network, Cloud SQL, compute, LB, CI/CD).

output "vpc_name" {
  description = "Name of the custom VPC."
  value       = module.network.vpc_name
}

output "vpc_self_link" {
  description = "Self link of the custom VPC."
  value       = module.network.vpc_self_link
}

output "app_subnet_name" {
  description = "Name of the application subnet."
  value       = module.network.app_subnet_name
}

output "app_subnet_self_link" {
  description = "Self link of the application subnet."
  value       = module.network.app_subnet_self_link
}

output "app_subnet_cidr" {
  description = "Primary CIDR range of the application subnet."
  value       = module.network.app_subnet_cidr
}

output "app_network_tag" {
  description = "Network tag to attach to application instances."
  value       = module.network.app_network_tag
}

output "psa_range_name" {
  description = "Name of the reserved Private Services Access range for Cloud SQL private IP."
  value       = module.network.psa_range_name
}

output "psa_range_address" {
  description = "Reserved PSA IP range (CIDR) for Cloud SQL private IP."
  value       = module.network.psa_range_address
}

output "service_networking_connection" {
  description = "Service Networking peering connection ID for Cloud SQL private connectivity."
  value       = module.network.service_networking_connection
}

output "cloud_router_name" {
  description = "Name of the Cloud Router backing Cloud NAT."
  value       = module.network.cloud_router_name
}

output "cloud_nat_name" {
  description = "Name of the Cloud NAT gateway for private-instance outbound access."
  value       = module.network.cloud_nat_name
}

# --- Cloud SQL ---------------------------------------------------------------

output "cloud_sql_instance_name" {
  description = "Cloud SQL instance name."
  value       = module.cloud_sql.instance_name
}

output "cloud_sql_private_ip" {
  description = "Private IP of the Cloud SQL instance (VPC-internal only)."
  value       = module.cloud_sql.private_ip_address
}

output "cloud_sql_connection_name" {
  description = "Connection name for the Cloud SQL Auth Proxy."
  value       = module.cloud_sql.instance_connection_name
}

output "cloud_sql_database_name" {
  description = "Application database name."
  value       = module.cloud_sql.database_name
}

output "cloud_sql_database_user" {
  description = "Application database user."
  value       = module.cloud_sql.database_user
}

output "cloud_sql_password_secret_id" {
  description = "Secret Manager secret ID holding the DB password."
  value       = module.cloud_sql.password_secret_id
}

# --- Compute tier ------------------------------------------------------------

output "app_service_account_email" {
  description = "Email of the application service account."
  value       = module.iam.service_account_email
}

output "instance_template_name" {
  description = "Name of the regional instance template."
  value       = module.instance_template.template_name
}

output "mig_name" {
  description = "Name of the regional Managed Instance Group."
  value       = module.mig.mig_name
}

output "mig_autoscaler_name" {
  description = "Name of the MIG autoscaler (null when autoscaling is disabled)."
  value       = module.mig.autoscaler_name
}

output "backend_service_name" {
  description = "Name of the regional backend service."
  value       = module.alb.backend_service_name
}

output "load_balancer_ip" {
  description = "External IP address of the Application Load Balancer."
  value       = module.alb.load_balancer_ip
}

output "http_url" {
  description = "HTTP URL of the Application Load Balancer."
  value       = module.alb.http_url
}

output "https_url" {
  description = "HTTPS URL (null until enable_https = true)."
  value       = module.alb.https_url
}

output "managed_cert_dns_records" {
  description = "DNS records to create for the Google-managed cert's DNS authorization (CNAME per domain). Add these + an A record (domain -> load_balancer_ip) at your DNS provider; the cert goes ACTIVE once they validate."
  value       = module.alb.managed_cert_dns_records
}

output "dns_zone_nameservers" {
  description = "Authoritative nameservers of the Cloud DNS zone. Delegate the domain to these at your registrar so the records resolve. Null when dns_zone_name is unset."
  value       = var.dns_zone_name == "" ? null : data.google_dns_managed_zone.app[0].name_servers
}

output "artifact_bucket_url" {
  description = "gs:// URL of the application artifact bucket (publish releases here)."
  value       = module.artifact_bucket.bucket_url
}

output "cicd_service_account_email" {
  description = "CI deploy service account (impersonated by GitHub Actions via WIF)."
  value       = module.cloud_build.ci_service_account_email
}

output "region" {
  description = "Deployment region (used by the deploy scripts)."
  value       = var.region
}

output "project_id" {
  description = "GCP project ID (used by the deploy scripts)."
  value       = var.project_id
}

# --- GitHub Actions (Workload Identity Federation) ---------------------------
# Copy these into the GitHub repo Environment variables (Settings -> Environments
# -> dev) so the keyless deploy workflow can authenticate. Null until
# enable_github_oidc = true.

output "github_actions_wif_provider" {
  description = "WIF provider resource name. Set as the 'dev' environment variable WIF_PROVIDER."
  value       = try(module.github_oidc[0].workload_identity_provider, null)
}

output "github_actions_deploy_sa" {
  description = "Service account GitHub Actions impersonates. Set as the 'dev' environment variable DEPLOY_SA."
  value       = try(module.github_oidc[0].deploy_service_account, null)
}
