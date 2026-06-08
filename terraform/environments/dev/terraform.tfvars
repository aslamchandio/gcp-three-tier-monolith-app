# environments/dev/terraform.tfvars
# Dev environment values. No secrets here (network layer only).

project_id  = "terraform-project-883456" # <-- replace with your dev GCP project
region      = "us-west1"
environment = "dev"
app_name    = "three-tier"

app_subnet_cidr   = "192.168.32.0/20"
psa_address       = "10.85.0.0" # Cloud SQL private IP range -> 10.85.0.0/16
psa_prefix_length = 16
app_port          = 8080

enable_flow_logs = true
nat_log_filter   = "ERRORS_ONLY"

# --- Database tier (Cloud SQL) ----------------------------------------------
db_version                    = "POSTGRES_15"
db_tier                       = "db-custom-1-3840"
db_availability_type          = "ZONAL" # dev: single zone to save cost
db_name                       = "appdb"
db_user                       = "appuser"
db_enable_deletion_protection = false # dev: allow easy teardown

# --- Application tier (compute / MIG) ---------------------------------------
machine_type   = "e2-medium"
instance_count = 2

# Regional ALB proxy-only subnet for the dev VPC (distinct from prod's).
proxy_subnet_cidr = "192.168.2.0/24"

# --- HTTPS (Google-managed cert via Certificate Manager) --------------------
# Phase 1: provision the cert + DNS authorization (enable_https stays false).
# After the CNAME (managed_cert_dns_records) + an A record are added and the
# cert reaches ACTIVE, flip enable_https = true to add :443 + the HTTP->HTTPS
# redirect.
managed_cert_domains = ["dev.nativeops.site"]
enable_https         = true # cert ACTIVE 2026-06-08 — :443 + HTTP->HTTPS redirect live

# Cloud DNS zone that hosts the domain — Terraform manages the cert-validation
# CNAME + the hostname A record (-> LB IP) for us.
dns_zone_name = "nativeops-site"

# --- Autoscaling (same design as prod) --------------------------------------
enable_autoscaling       = true
min_replicas             = 2
max_replicas             = 4
autoscaling_cpu_target   = 0.6
autoscaling_cooldown_sec = 90

# --- Keyless CI/CD (GitHub Actions via Workload Identity Federation) --------
enable_github_oidc = true
github_owner       = "aslamchandio"
github_repo        = "gcp-three-tier-monolith-app"

labels = {
  owner = "platform-team"
  cost  = "three-tier-dev"
}
