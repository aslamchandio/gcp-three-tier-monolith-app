# environments/prod/terraform.tfvars
# Prod environment values. No secrets here (network layer only).
# Non-overlapping CIDR vs dev so the environments can peer/coexist later.

project_id  = "Project-1234" # <-- replace with your prod GCP project
region      = "us-central1"
environment = "prod"
app_name    = "three-tier"

app_subnet_cidr   = "192.168.16.0/20"
psa_address       = "10.77.0.0" # explicit PSA start IP -> 10.77.0.0/16
psa_prefix_length = 16
app_port          = 8080

enable_flow_logs = true
nat_log_filter   = "ERRORS_ONLY"

# --- HTTPS (Google-managed cert via Certificate Manager) --------------------
# Phase 1: provision the cert + DNS (validation CNAME + A record) in the shared
# Cloud DNS zone "nativeops-site" while enable_https stays false — prod keeps
# serving HTTP with no disruption. Flip enable_https = true (Phase 2) only once
# the cert reaches ACTIVE to add :443 + the HTTP->HTTPS redirect.
managed_cert_domains = ["prod.nativeops.site"]
dns_zone_name        = "nativeops-site"
enable_https         = true # cert ACTIVE 2026-06-08 — :443 + HTTP->HTTPS redirect live

# --- Application tier autoscaling --------------------------------------------
enable_autoscaling       = true
min_replicas             = 2   # floor: keep HA across zones
max_replicas             = 6   # ceiling for traffic spikes
autoscaling_cpu_target   = 0.6 # scale out when avg CPU exceeds 60%
autoscaling_cooldown_sec = 90

# --- Keyless CI/CD (GitHub Actions via Workload Identity Federation) --------
# Prod is branch-scoped: only the main branch can mint deploy-capable tokens.
enable_github_oidc = true
github_owner       = "aslamchandio"
github_repo        = "gcp-three-tier-monolith-app"
github_ref         = "refs/heads/main"

labels = {
  owner = "platform-team"
  cost  = "three-tier-prod"
}
