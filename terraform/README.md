# Terraform — GCP Three-Tier Monolith Infrastructure

Infrastructure as Code for a production-style three-tier application on GCP.
Reusable **modules** are composed by per-**environment** roots, each with its own
isolated remote state.

Both environments now run the **full stack** (network → Cloud SQL → compute →
ALB → CI/CD), each in its own VPC and GCS state prefix:

```
terraform/
├── environments/
│   ├── dev/        # state prefix: dev/three-tier-tfstate   — us-west1,   full stack
│   └── prod/       # state prefix: prod/three-tier-tfstate  — us-central1, full stack
└── modules/
    ├── network/                 # VPC, app subnet, PSA, Cloud Router/NAT, firewall
    ├── cloud-sql/               # PostgreSQL, PRIVATE IP only, Secret Manager password
    ├── iam/                     # app service account + least-privilege roles
    ├── secret-manager/          # create secrets / grant secretAccessor
    ├── gcs-bucket/              # private versioned artifact bucket
    ├── instance-template/       # app instance template (no external IP, Shielded VM)
    ├── health-check/            # regional HTTP health check (liveness /healthz, readiness /readyz)
    ├── managed-instance-group/  # regional MIG (named port, autoheal, CPU autoscaler, rolling update)
    ├── alb/                     # regional external ALB + proxy-only subnet + proxy firewall
    ├── cloud-build/             # CI deploy service account + least-privilege IAM
    └── github-oidc/             # Workload Identity Federation for keyless GitHub Actions
```

## Conventions

- **Naming:** `<app_name>-<environment>-<resource>` (e.g. `three-tier-prod-vpc`).
- **No hardcoding:** project IDs, regions, environments, and secrets are all
  variables. Backends set the bucket literally (backends can't interpolate).
- **State isolation:** each environment uses a distinct GCS prefix, so an apply
  in one environment can never affect another.
- **Module contract:** every module declares typed/validated variables, useful
  outputs, and a `versions.tf` with `required_providers` only (no backend, no
  version pin — those live in the environment roots).
- **Labels** are applied via the provider `default_labels` for cost tracking.

## Modules

| Module | Creates | Key guarantees |
|--------|---------|----------------|
| `network` | Custom VPC, app subnet (Private Google Access + flow logs), PSA range + Service Networking peering, Cloud Router + NAT, least-privilege firewall | No default VPC; no public SSH; instances designed for no external IP |
| `cloud-sql` | PostgreSQL instance, database, user, generated password in Secret Manager | **Private IP only** (`ipv4_enabled = false`), TLS enforced, backups, deletion protection |
| `iam` | App service account + project roles | Least privilege: `logging.logWriter`, `monitoring.metricWriter`, `cloudsql.client`; rejects owner/editor |
| `secret-manager` | Secrets + `secretAccessor` grants (incl. on existing secrets) | Values never hardcoded (sensitive); grants scoped per secret |
| `instance-template` | Regional app instance template | No external IP, Shielded VM, runs as the app SA, startup script from `ecommerce-app/deploy/startup.sh` |
| `health-check` | Regional HTTP health check on `:8080` | Path is a variable: MIG uses `/healthz` (liveness), the LB backend uses `/readyz` (readiness) |
| `managed-instance-group` | Regional MIG + autoscaler | Named port 8080, autohealing, proactive rolling updates; CPU-driven autoscaler (min 2) with scale-in control |
| `alb` | Regional external ALB | HTTP (+ optional HTTPS with HTTP→HTTPS redirect) via a **Google-managed cert** (Certificate Manager + DNS authorization) or a self-managed cert, backend logging, proxy-only subnet, **and a firewall rule allowing that proxy subnet → app port** |
| `gcs-bucket` | Private versioned GCS bucket | Uniform access, public-access prevention, `objectViewer` grants |
| `cloud-build` | CI deploy service account + least-privilege IAM | No JSON keys; scoped to write the artifact bucket, roll the MIG, and `actAs` the app SA |
| `github-oidc` | Workload Identity Federation pool/provider + impersonation binding | Keyless GitHub Actions; locked to the repo owner, optionally to a single branch (prod → `main`) |

---

## Compute Tier (this phase)

The compute tier turns the already-provisioned network + Cloud SQL into a
running, load-balanced application. It is built from six modules wired in
dependency order:

```
                         Internet
                            │
              ┌─────────────▼──────────────┐
              │  Regional External ALB     │   (alb module)
              │  :80 (HTTP)  [opt :443]     │
              │   Backend service │ (logs)  │◄── LB health check (/readyz:8080)
              └──────────┬────────┘         │
                         │ proxy-only subnet ─► firewall allow → :8080
                         │ named port "http":8080
                ┌────────▼─────────┐
                │ Regional MIG     │  (managed-instance-group)
                │ autoheal + roll  │◄── autoheal health check (/healthz:8080)
                │ + CPU autoscaler │
                └────────┬─────────┘
                         │ uses
                ┌────────▼─────────┐
                │ Instance template│  (instance-template)
                │ no ext IP·Shielded│
                │ runs as app SA   │◄── iam (SA + roles)
                │ startup.sh       │──► pulls app from artifact bucket (gcs-bucket)
                └────────┬─────────┘
                         │ at boot: reads secret, connects private IP
            ┌────────────▼─────────────┐
            │ Cloud SQL (private IP)   │
            │ password ← Secret Manager│◄── secret-manager (grant SA access)
            └──────────────────────────┘
```

**What each module contributes**

1. **iam** — creates the application service account and grants least-privilege
   roles (`logging.logWriter`, `monitoring.metricWriter`, `cloudsql.client`).
2. **secret-manager** — grants the SA `roles/secretmanager.secretAccessor` on the
   DB password secret (and any app-config secrets). Granting at the **secret
   scope** is stricter than a project-wide role.
3. **instance-template** — regional app template: **no external IP** (egress via
   Cloud NAT), Shielded VM, network tag matching the firewall, runs as the SA,
   and uses `ecommerce-app/deploy/startup.sh` as the metadata `startup-script`. Non-secret
   config (DB private IP, names, port, the password **secret id**) is passed via
   instance metadata; the DB password is fetched from Secret Manager at boot.
4. **health-check** — regional HTTP probes on `:8080`. Two are wired: the MIG
   autoheal probe hits `/healthz` (liveness — recreate only dead processes); the
   LB backend probe hits `/readyz` (readiness — route only to instances whose DB
   is reachable).
5. **managed-instance-group** — regional MIG with named port `http:8080`,
   autohealing, and a proactive rolling-update policy. A CPU-driven
   **autoscaler** (min 2) owns the size when `enable_autoscaling = true`, with a
   scale-in control so the group never shrinks too fast after a spike.
6. **alb** — regional external ALB: a backend service (MIG attached, **logging
   enabled**) behind an HTTP listener, with an optional HTTPS listener and an
   HTTP→HTTPS redirect. For HTTPS it provisions a **Google-managed certificate**
   (Certificate Manager + per-domain DNS authorization) when `managed_cert_domains`
   is set, or falls back to a self-managed cert/key. The cert + DNS authorizations
   are created **independently of `enable_https`** (so the cert can reach ACTIVE
   before the `:443` listener is switched on); the `managed_cert_dns_records`
   output surfaces the validation CNAME(s) to publish. Creates the required
   proxy-only subnet **and a firewall rule allowing that proxy subnet to reach the
   app port** — without it a regional Envoy LB cannot deliver requests even though
   backends report HEALTHY.

> The application instances are never publicly reachable — only the load balancer
> receives external traffic, and the database is reachable only over the VPC
> private IP.

### Example wiring (in an environment root)

```hcl
module "iam" {
  source        = "../../modules/iam"
  project_id    = var.project_id
  app_name      = var.app_name
  environment   = var.environment
  project_roles = ["roles/logging.logWriter", "roles/monitoring.metricWriter", "roles/cloudsql.client"]
}

module "secret_manager" {
  source     = "../../modules/secret-manager"
  project_id = var.project_id
  # Grant the SA access to the existing Cloud SQL password secret.
  external_accessors = {
    (var.db_password_secret_id) = [module.iam.service_account_member]
  }
}

module "instance_template" {
  source                = "../../modules/instance-template"
  project_id            = var.project_id
  app_name              = var.app_name
  environment           = var.environment
  machine_type          = var.machine_type
  network               = var.vpc_self_link
  subnetwork            = var.subnet_self_link
  network_tags          = [var.app_network_tag]
  service_account_email = module.iam.service_account_email
  startup_script        = file("../../../ecommerce-app/deploy/startup.sh")
  metadata = {
    environment           = var.environment
    app_port              = tostring(var.app_port)
    db_host               = var.cloud_sql_private_ip      # existing Cloud SQL private IP
    db_name               = var.db_name
    db_user               = var.db_user
    db_password_secret_id = var.db_password_secret_id
  }
  labels = local.labels
}

module "health_check" {
  source            = "../../modules/health-check"
  project_id        = var.project_id
  region            = var.region
  app_name          = var.app_name
  environment       = var.environment
  app_port          = var.app_port
  health_check_path = var.health_check_path
}

module "mig" {
  source                 = "../../modules/managed-instance-group"
  project_id             = var.project_id
  region                 = var.region
  app_name               = var.app_name
  environment            = var.environment
  instance_template      = module.instance_template.template_self_link
  instance_count         = var.instance_count   # used only when autoscaling is off
  app_port               = var.app_port
  health_check_self_link = module.health_check_mig.health_check_self_link

  # CPU-driven autoscaling (the autoscaler owns the size; target_size is ignored).
  enable_autoscaling     = true
  min_replicas           = 2
  max_replicas           = 6
  autoscaling_cpu_target = 0.6
}

module "alb" {
  source                 = "../../modules/alb"
  project_id             = var.project_id
  region                 = var.region
  app_name               = var.app_name
  environment            = var.environment
  vpc_self_link          = var.vpc_self_link
  instance_group         = module.mig.instance_group
  health_check_self_link = module.health_check_lb.health_check_self_link

  # Required for a regional Envoy LB: allow the proxy-only subnet → app port.
  backend_network_tags = [var.app_network_tag]
  app_port             = var.app_port

  # HTTPS via a Google-managed cert. Provision the cert first (enable_https =
  # false), publish the validation CNAME (managed_cert_dns_records output) + an
  # A record, then flip enable_https = true once the cert is ACTIVE.
  managed_cert_domains = var.managed_cert_domains # e.g. ["dev.nativeops.site"]
  enable_https         = var.enable_https
}
```

> **Phased HTTPS rollout (avoids a redirect-to-dead-TLS window).** Because a
> Google-managed cert only goes ACTIVE after its DNS authorization validates,
> roll out in two applies: **(1)** set `managed_cert_domains` + `dns_zone_name`
> with `enable_https = false` — provisions the cert and (when `dns_zone_name` is
> set) the validation CNAME + hostname A record in Cloud DNS while traffic stays
> on HTTP; **(2)** once the cert reports `ACTIVE`, set `enable_https = true` to
> add the `:443` listener and the HTTP→HTTPS redirect. **Changing a domain on an
> existing cert is a cert _replacement_** while it's attached to the live `:443`
> proxy — set `enable_https = false` for the swap, then re-enable, to avoid an
> in-use error and a TLS gap.

---

---

## CI/CD — automatic artifact delivery (GitHub Actions, keyless)

The app is delivered as a **versioned GCS artifact** (the prod-grade pattern;
see the project README). GitHub Actions, on every push to `main` touching
`ecommerce-app/`:

1. **tests** the app (`ruff` + `pytest`) — bad code never ships,
2. **publishes** it to `gs://<artifact-bucket>/releases/<sha>/` and updates
   `gs://<artifact-bucket>/current/` (what the VMs pull),
3. **rolls the MIG** (`rolling-action replace`, surge-first = zero downtime) so
   instances re-run `startup.sh` and pick up the new code,
4. **smoke-tests** the rollout — once the MIG is stable it requires
   `<APP_URL>/readyz` to report ready through the load balancer (enable by
   setting the `APP_URL` variable on each GitHub Environment).

On pull requests, `ci.yml` additionally gates on `ruff` + `pytest` (both apps),
`terraform fmt`/`validate` (dev + prod), and a **Trivy IaC misconfiguration
scan** of `terraform/` (report-only until findings are triaged); superseded PR
runs are auto-cancelled via a concurrency group.

The pipeline authenticates with **no long-lived credentials**: it presents a
short-lived GitHub OIDC token and, via **Workload Identity Federation**,
impersonates a **dedicated, least-privilege CI service account** (no JSON keys).
That SA has only: `objectAdmin` on the artifact bucket, `compute.instanceAdmin.v1`
to roll the MIG, a custom role for `compute.regionHealthChecks.use`,
`logging.logWriter`, and `serviceAccountUser` on the app SA.

### Enable it (one-time)

```bash
# Turn WIF on in terraform.tfvars (per environment):
#    enable_github_oidc = true
#    github_owner       = "your-org"
#    github_repo        = "gcp-three-tier-monolith-repo"
#    github_ref         = "refs/heads/main"   # recommended for prod (branch-locked)

cd terraform/environments/prod
terraform plan -out=tfplan && terraform apply tfplan
```

Then set the per-environment GitHub Environment secrets/variables and run the
workflow. Full setup, rollback, and hardening notes live in
[`CICD.md`](../CICD.md).

---

## Required GCP APIs

```bash
gcloud services enable \
  compute.googleapis.com \
  sqladmin.googleapis.com \
  servicenetworking.googleapis.com \
  secretmanager.googleapis.com \
  storage.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
  certificatemanager.googleapis.com \
  dns.googleapis.com \
  --project="<YOUR_PROJECT_ID>"
```

## Deployment workflow

Run from the target environment folder (each has isolated state). Because the
VMs pull the app from the artifact bucket **on first boot**, stage the app before
the MIG comes up:

```bash
cd terraform/environments/prod      # or dev
terraform init                      # configures the GCS backend
terraform fmt -recursive
terraform validate

# 1. Bootstrap the artifact bucket (+ its IAM) first.
terraform apply -target=module.iam -target=module.artifact_bucket

# 2. Publish the app to what the VMs pull (GitHub Actions deploy, or rsync the app tree).
gsutil -m rsync -r ../../../ecommerce-app gs://<PROJECT>-three-tier-<env>-artifacts/current

# 3. Apply the rest of the stack.
terraform plan -out=tfplan
terraform apply tfplan
```

State buckets must exist beforehand (versioning on). Both environments use
`bucket-tf-1234` with prefixes `dev/three-tier-tfstate` and
`prod/three-tier-tfstate`. The bucket is set in each `backend.tf`, or pass
`-backend-config="bucket=<name>"` at init.

## Operational gotchas (learned in production)

- **Regional ALB → "upstream request timeout" with HEALTHY backends.** A regional
  Envoy LB serves traffic from the **proxy-only subnet**, not from the Google
  health-check ranges. If the firewall only allows the health-check ranges, health
  is green but real requests are dropped. The `alb` module's
  `allow_proxy_to_backends` firewall rule fixes this — keep `backend_network_tags`
  wired. ("no healthy upstream" instead means the app/health check is genuinely
  failing.)
- **Cloud SQL create-wait can time out while the instance keeps building.**
  Terraform may report `Error waiting for Create Instance` (empty message) after
  ~2 min while the GCP operation is still `RUNNING`. Don't recreate — instead:
  ```bash
  gcloud sql operations wait <OP_ID> --project=<PROJECT> --timeout=unlimited
  terraform import module.cloud_sql.google_sql_database_instance.postgres \
    projects/<PROJECT>/instances/three-tier-<env>-pg
  terraform apply        # continues with DB, user, compute, ALB
  ```
- **Changing region after bootstrap moves the artifact bucket** (location is
  immutable → replacement). Republish the app to the new-region bucket before the
  MIG boots.
- **Concurrent DB migrations during a rolling deploy.** Every VM runs
  `alembic upgrade head` in its `startup.sh` on boot. A deploy does
  `rolling-action replace ... --max-surge=3`, so **up to 3 new VMs boot at once
  and each tries to migrate the same database simultaneously**. Today this is
  harmless only because the schema is already at `head` — every run is a no-op.
  The next time a release adds a migration, those parallel `upgrade head` calls
  race on the _same_ schema change (duplicate DDL, half-applied steps, or an
  Alembic version-table conflict) — a class of failure that stays invisible until
  the one deploy that actually changes the schema.

  Why not migrate from CI instead (the usual answer)? **Cloud SQL here is
  private-IP only** — the GitHub Actions runner has no route to it, so migrations
  must run from inside the VPC, i.e. on the VMs. The fix that fits this
  architecture is to **serialize** the migration with a PostgreSQL _advisory
  lock_: before `alembic upgrade head`, each VM calls `pg_advisory_lock(<key>)`.
  The first VM gets the lock and migrates; the others block until it finishes,
  then run `upgrade head` as a clean no-op and release. One migration at a time,
  no architecture change, rolls out on the next normal deploy.

  ```bash
  # startup.sh holds the lock inside ONE psql session for the whole migration —
  # alembic runs from that session via psql's \!, so the lock can't be released
  # early and auto-releases if the VM dies mid-migration:
  #   psql ... <<SQL
  #   SELECT pg_advisory_lock(727274);          -- blocks until free
  #   \! sh -c 'cd "$APP_DIR" && alembic upgrade head'
  #   SELECT pg_advisory_unlock(727274);
  #   SQL
  ```

  > Status: **implemented** in `ecommerce-app/deploy/startup.sh`
  > (psql advisory lock; `postgresql-client`
  > added to the VM packages, `PGSSLMODE=require` for the ENCRYPTED_ONLY
  > instance). Rolls out on the next deploy — no `terraform apply` needed.

## Cleanup

```bash
cd terraform/environments/prod
terraform destroy
```

The Service Networking peering uses `deletion_policy = "ABANDON"` for clean
teardown. Cloud SQL has deletion protection — disable it first if you must
destroy the database.
