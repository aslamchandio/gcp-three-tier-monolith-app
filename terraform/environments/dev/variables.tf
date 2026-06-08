# environments/dev/variables.tf

variable "project_id" {
  description = "GCP project ID for the dev environment. No default — must be provided."
  type        = string

  validation {
    condition     = length(var.project_id) > 0
    error_message = "project_id must not be empty."
  }
}

variable "region" {
  description = "GCP region for regional resources (subnet, Cloud Router, Cloud NAT)."
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Deployment environment. Used in resource names and labels."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be one of: dev, stage, prod."
  }
}

variable "app_name" {
  description = "Application/project short name. Used as the naming prefix."
  type        = string
  default     = "three-tier"
}

variable "network_name" {
  description = "Optional explicit VPC name. If empty, derived as <app_name>-<environment>-vpc."
  type        = string
  default     = ""
}

variable "app_subnet_cidr" {
  description = "Primary CIDR range for the application subnet."
  type        = string
  default     = "10.10.1.0/24"

  validation {
    condition     = can(cidrhost(var.app_subnet_cidr, 0))
    error_message = "app_subnet_cidr must be a valid IPv4 CIDR (e.g. 10.10.1.0/24)."
  }
}

variable "psa_address" {
  description = "Optional explicit start IP for the Private Services Access range (e.g. 10.77.0.0). If empty, GCP auto-allocates."
  type        = string
  default     = ""

  validation {
    condition     = var.psa_address == "" || can(cidrhost("${var.psa_address}/32", 0))
    error_message = "psa_address must be empty or a valid IPv4 address (e.g. 10.77.0.0)."
  }
}

variable "psa_prefix_length" {
  description = "Prefix length for the Private Services Access range reserved for Cloud SQL private IP."
  type        = number
  default     = 16

  validation {
    condition     = var.psa_prefix_length >= 16 && var.psa_prefix_length <= 24
    error_message = "psa_prefix_length must be between 16 and 24."
  }
}

variable "app_port" {
  description = "Internal application port the backend instances listen on (also the health check port)."
  type        = number
  default     = 8080
}

variable "iap_source_range" {
  description = "Google Identity-Aware Proxy TCP forwarding source range for SSH."
  type        = string
  default     = "35.235.240.0/20"
}

variable "health_check_source_ranges" {
  description = "Google load balancer health check / proxy source ranges."
  type        = list(string)
  default     = ["35.191.0.0/16", "130.211.0.0/22"]
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs on the application subnet."
  type        = bool
  default     = true
}

variable "nat_log_filter" {
  description = "Cloud NAT logging filter: ERRORS_ONLY, TRANSLATIONS_ONLY, or ALL."
  type        = string
  default     = "ERRORS_ONLY"

  validation {
    condition     = contains(["ERRORS_ONLY", "TRANSLATIONS_ONLY", "ALL"], var.nat_log_filter)
    error_message = "nat_log_filter must be one of: ERRORS_ONLY, TRANSLATIONS_ONLY, ALL."
  }
}

variable "labels" {
  description = "Additional labels merged onto resources that support labels (cost tracking)."
  type        = map(string)
  default     = {}
}

# --- Cloud SQL ---------------------------------------------------------------

variable "db_version" {
  description = "Cloud SQL PostgreSQL engine version."
  type        = string
  default     = "POSTGRES_15"
}

variable "db_tier" {
  description = "Cloud SQL machine tier."
  type        = string
  default     = "db-custom-1-3840"
}

variable "db_availability_type" {
  description = "ZONAL or REGIONAL (ZONAL for dev to save cost)."
  type        = string
  default     = "ZONAL"
}

variable "db_name" {
  description = "Application database name."
  type        = string
  default     = "appdb"
}

variable "db_user" {
  description = "Application database user."
  type        = string
  default     = "appuser"
}

variable "db_password" {
  description = "Optional DB password. If empty, Terraform generates a strong one and stores it in Secret Manager."
  type        = string
  default     = ""
  sensitive   = true
}

# --- Compute tier ------------------------------------------------------------

variable "machine_type" {
  description = "Machine type for application instances."
  type        = string
  default     = "e2-medium"
}

variable "instance_count" {
  description = "Fixed number of application instances when autoscaling is disabled."
  type        = number
  default     = 2
}

# --- Autoscaling -------------------------------------------------------------
variable "enable_autoscaling" {
  description = "Attach a CPU-driven regional autoscaler to the MIG. When true the autoscaler owns the instance count."
  type        = bool
  default     = true
}

variable "min_replicas" {
  description = "Minimum instances the autoscaler maintains."
  type        = number
  default     = 2
}

variable "max_replicas" {
  description = "Maximum instances the autoscaler may create."
  type        = number
  default     = 4
}

variable "autoscaling_cpu_target" {
  description = "Target average CPU utilization (0.0-1.0) that drives scaling."
  type        = number
  default     = 0.6
}

variable "autoscaling_cooldown_sec" {
  description = "Seconds the autoscaler waits for a new instance to warm up before using its metrics."
  type        = number
  default     = 90
}

variable "mig_health_check_path" {
  description = "Liveness path for MIG autohealing (only recreate dead processes)."
  type        = string
  default     = "/healthz"
}

variable "lb_health_check_path" {
  description = "Readiness path for the load balancer backend (only route to instances that can serve)."
  type        = string
  default     = "/readyz"
}

variable "proxy_subnet_cidr" {
  description = "CIDR for the regional ALB proxy-only subnet. Must not overlap other subnets in this VPC."
  type        = string
  default     = "192.168.2.0/24"
}

# --- HTTPS (Google-managed cert via Certificate Manager) ---------------------
variable "managed_cert_domains" {
  description = "Domains for the dev Google-managed TLS certificate (Certificate Manager, DNS authorization). Provisioning the cert is independent of enable_https; see the managed_cert_dns_records output for the CNAME(s) to create, plus an A record pointing each domain at the LB IP."
  type        = list(string)
  default     = []
}

variable "enable_https" {
  description = "Add the HTTPS :443 listener and the HTTP->HTTPS redirect. Turn on only after the managed certificate is ACTIVE, or the redirect will send clients to a listener that can't complete TLS."
  type        = bool
  default     = false
}

variable "dns_zone_name" {
  description = "Cloud DNS managed-zone NAME (not the dnsName) that hosts managed_cert_domains. When set, Terraform creates the cert-validation CNAME and the hostname A record in this zone. Leave empty to manage DNS yourself."
  type        = string
  default     = ""
}

variable "dns_zone_project" {
  description = "Project that owns the Cloud DNS zone, if different from project_id. Empty = use project_id."
  type        = string
  default     = ""
}

variable "artifact_bucket_force_destroy" {
  description = "Allow Terraform to delete the (non-empty) artifact bucket. Convenient in dev for clean teardown."
  type        = bool
  default     = true
}

variable "app_artifact_subpath" {
  description = "Prefix within the artifact bucket the startup script syncs the app from."
  type        = string
  default     = "current"
}

# --- Keyless CI/CD (GitHub Actions via Workload Identity Federation) ---------

variable "github_owner" {
  description = "GitHub repository owner/org (required when enable_github_oidc = true)."
  type        = string
  default     = ""
}

variable "github_repo" {
  description = "GitHub repository name (required when enable_github_oidc = true)."
  type        = string
  default     = ""
}

variable "enable_github_oidc" {
  description = "Create a Workload Identity Federation pool/provider so GitHub Actions can deploy keylessly by impersonating the CI service account. Requires github_owner/github_repo."
  type        = bool
  default     = false
}

variable "github_ref" {
  description = "Optional git ref to lock keyless deploys to (e.g. 'refs/heads/main'). When set, only that branch can impersonate the CI service account. Empty (default) allows any branch in the repo. Recommended 'refs/heads/main' for prod."
  type        = string
  default     = ""
}

variable "db_enable_deletion_protection" {
  description = "Protect the Cloud SQL instance from deletion. Off in dev for easy teardown."
  type        = bool
  default     = false
}
