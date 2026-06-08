# environments/prod/main.tf
# PROD composition: wires prod values into the shared network module.

locals {
  labels = merge(
    {
      app         = var.app_name
      environment = var.environment
      managed_by  = "terraform"
      tier        = "network"
    },
    var.labels,
  )
}

module "network" {
  source = "../../modules/network"

  project_id  = var.project_id
  region      = var.region
  app_name    = var.app_name
  environment = var.environment

  network_name               = var.network_name
  app_subnet_cidr            = var.app_subnet_cidr
  psa_address                = var.psa_address
  psa_prefix_length          = var.psa_prefix_length
  app_port                   = var.app_port
  iap_source_range           = var.iap_source_range
  health_check_source_ranges = var.health_check_source_ranges
  enable_flow_logs           = var.enable_flow_logs
  nat_log_filter             = var.nat_log_filter
}

module "cloud_sql" {
  source = "../../modules/cloud-sql"

  project_id  = var.project_id
  region      = var.region
  app_name    = var.app_name
  environment = var.environment

  # Private IP draws from the PSA range created by the network module.
  network_id = module.network.vpc_self_link

  database_version           = var.db_version
  tier                       = var.db_tier
  availability_type          = var.db_availability_type
  db_name                    = var.db_name
  db_user                    = var.db_user
  db_password                = var.db_password
  enable_deletion_protection = var.db_enable_deletion_protection
  labels                     = local.labels

  # Critical: the private IP needs the Service Networking peering to exist first.
  depends_on = [module.network]
}

# ---------------------------------------------------------------------------
# Compute tier: SA + secret access -> instance template -> MIG -> health check
# -> regional Application Load Balancer (HTTPS via a Google-managed cert).
# ---------------------------------------------------------------------------

module "iam" {
  source = "../../modules/iam"

  project_id  = var.project_id
  app_name    = var.app_name
  environment = var.environment

  project_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudsql.client",
  ]
}

# Grant the app service account secretAccessor on the EXISTING Cloud SQL
# password secret (created by the cloud-sql module) — scoped to that secret.
module "secret_manager" {
  source = "../../modules/secret-manager"

  project_id = var.project_id
  labels     = local.labels

  external_accessors = {
    (module.cloud_sql.password_secret_id) = [module.iam.service_account_member]
  }
}

# Private, versioned bucket for application artifacts. The app SA gets read-only
# access; the startup script pulls the code from here at boot.
module "artifact_bucket" {
  source = "../../modules/gcs-bucket"

  project_id    = var.project_id
  name          = "${var.project_id}-${var.app_name}-${var.environment}-artifacts"
  location      = var.region
  force_destroy = var.artifact_bucket_force_destroy
  viewers       = [module.iam.service_account_member]
  labels        = local.labels
}

module "instance_template" {
  source = "../../modules/instance-template"

  project_id  = var.project_id
  region      = var.region
  app_name    = var.app_name
  environment = var.environment

  machine_type = var.machine_type
  network      = module.network.vpc_self_link
  subnetwork   = module.network.app_subnet_self_link
  network_tags = [module.network.app_network_tag]

  service_account_email = module.iam.service_account_email

  # Bootstrap the app from the repo's startup script.
  startup_script = file("../../../app/deploy/startup.sh")

  # Non-secret config via metadata; the DB password is fetched from Secret
  # Manager at boot (the SA was granted access above).
  metadata = {
    environment           = var.environment
    app_port              = tostring(var.app_port)
    db_host               = module.cloud_sql.private_ip_address # existing Cloud SQL private IP
    db_port               = "5432"
    db_name               = module.cloud_sql.database_name
    db_user               = module.cloud_sql.database_user
    db_password_secret_id = module.cloud_sql.password_secret_id
    db_max_connections    = "10"

    # Startup script pulls the app from this prefix (publish artifacts here).
    code_bucket = "${module.artifact_bucket.bucket_url}/${var.app_artifact_subpath}"
  }

  labels = local.labels
}

# Autohealing health check (LIVENESS /healthz): conservative so a DB blip never
# triggers an instance-recreation storm. Only kills truly-dead processes.
module "health_check_mig" {
  source = "../../modules/health-check"

  project_id  = var.project_id
  region      = var.region
  app_name    = var.app_name
  environment = var.environment

  name_suffix         = "mig-hc"
  app_port            = var.app_port
  health_check_path   = var.mig_health_check_path
  check_interval_sec  = 15
  timeout_sec         = 5
  unhealthy_threshold = 5
}

# Load balancer health check (READINESS /readyz): stops routing traffic to
# instances that cannot serve (e.g. DB unreachable), without recreating them.
module "health_check_lb" {
  source = "../../modules/health-check"

  project_id  = var.project_id
  region      = var.region
  app_name    = var.app_name
  environment = var.environment

  name_suffix       = "lb-hc"
  app_port          = var.app_port
  health_check_path = var.lb_health_check_path
}

module "mig" {
  source = "../../modules/managed-instance-group"

  project_id  = var.project_id
  region      = var.region
  app_name    = var.app_name
  environment = var.environment

  instance_template      = module.instance_template.template_self_link
  instance_count         = var.instance_count
  app_port               = var.app_port
  health_check_self_link = module.health_check_mig.health_check_self_link

  # Autoscaling (CPU-driven, with scale-in control).
  enable_autoscaling       = var.enable_autoscaling
  min_replicas             = var.min_replicas
  max_replicas             = var.max_replicas
  autoscaling_cpu_target   = var.autoscaling_cpu_target
  autoscaling_cooldown_sec = var.autoscaling_cooldown_sec
}

module "alb" {
  source = "../../modules/alb"

  project_id  = var.project_id
  region      = var.region
  app_name    = var.app_name
  environment = var.environment

  vpc_self_link          = module.network.vpc_self_link
  instance_group         = module.mig.instance_group
  health_check_self_link = module.health_check_lb.health_check_self_link

  # Regional Envoy ALB serves traffic from the proxy-only subnet, so the backend
  # firewall must allow that range to the app port (scoped to the app tag).
  backend_network_tags = [module.network.app_network_tag]
  app_port             = var.app_port

  # The cert + DNS authorizations are provisioned whenever managed_cert_domains
  # is set; flip enable_https=true to add the :443 listener + HTTP->HTTPS redirect
  # only once the cert is ACTIVE (see managed_cert_dns_records output).
  enable_https         = var.enable_https
  managed_cert_domains = var.managed_cert_domains
  create_proxy_subnet  = true
  proxy_subnet_cidr    = var.proxy_subnet_cidr
}

# CI deploy identity: a least-privilege service account that GitHub Actions
# impersonates via WIF (see modules/github-oidc) to publish the app artifact
# and roll the MIG. No JSON keys are created.
module "cloud_build" {
  source = "../../modules/cloud-build"

  project_id  = var.project_id
  app_name    = var.app_name
  environment = var.environment

  artifact_bucket_name   = module.artifact_bucket.bucket_name
  app_service_account_id = module.iam.service_account_id
}

# Keyless GitHub Actions -> GCP auth (Workload Identity Federation). Gated by
# enable_github_oidc so it only applies when opted in. Reuses the cloud-build
# CI service account, so GitHub Actions and Cloud Build share one identity.
module "github_oidc" {
  source = "../../modules/github-oidc"
  count  = var.enable_github_oidc ? 1 : 0

  project_id  = var.project_id
  app_name    = var.app_name
  environment = var.environment

  github_owner = var.github_owner
  github_repo  = var.github_repo
  github_ref   = var.github_ref

  service_account_email = module.cloud_build.ci_service_account_email
}
