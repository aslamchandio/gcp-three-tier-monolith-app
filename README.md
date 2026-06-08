# GCP Three-Tier Monolith — App + Infrastructure

A production-style **three-tier monolithic application** on Google Cloud,
provisioned with **Terraform** and implemented as a single-process **FastAPI**
app. The application is a monolith; the infrastructure follows a three-tier
design. Keyless **GitHub Actions** lint/test the app, validate + security-scan
the Terraform, and deploy via Workload Identity Federation.

```
                          Internet
                             │
                             ▼
         ┌──────────────────────────────────────────────┐
   Web   │  Regional External Application Load Balancer  │  HTTPS + HTTP→HTTPS redirect
  tier   └───────────────────────┬──────────────────────┘
                                 │  backend service (logging)
                                 ▼
         ┌──────────────────────────────────────────────┐
  App    │  Managed Instance Group (regional)            │
  tier   │  Compute Engine · no external IP · :8080      │  egress via Cloud NAT
         │  FastAPI app · runs as least-priv SA          │
         └───────────────────────┬──────────────────────┘
                                 │  private IP + Secret Manager password
                                 ▼
         ┌──────────────────────────────────────────────┐
  Data   │  Cloud SQL for PostgreSQL · PRIVATE IP only   │
  tier   └──────────────────────────────────────────────┘
```

## Repository layout

```
gcp-three-tier-monolith-app/
├── README.md                # this file — whole-project overview
├── ecommerce-app/           # Nova Store FastAPI monolith (the application tier)
│   ├── src/monolith/        #   api → services → repositories (catalog/cart/checkout)
│   ├── migrations/          #   Alembic (0001 → 0002 e-commerce schema)
│   └── deploy/              #   startup.sh + systemd unit
├── terraform/               # infrastructure (modules + per-env roots)
│   ├── environments/        #   dev / prod roots, isolated remote state
│   └── modules/             #   reusable building blocks (network, alb, cloud-sql, …)
└── .github/workflows/       # CI (lint/test/validate/scan) + keyless deploy (WIF)
```

READMEs, by scope:
- **This file** — architecture and how the pieces fit together.
- [`ecommerce-app/README.md`](ecommerce-app/README.md) — Nova Store: merged
  services, endpoints, run locally, deploy.
- [`terraform/README.md`](terraform/README.md) — modules, environments, compute
  tier, deployment workflow.

## The application

**Nova Store** ([`ecommerce-app/`](ecommerce-app/)) is a layered monolith (one
process) folded from a polyglot microservices app into one process over one
PostgreSQL database (tables `products`, `cart_items`, `orders`, `order_items`):

| Layer | Responsibility |
|-------|----------------|
| Presentation (`api/`) | HTTP routes, validation, serialization, HTML pages |
| Business (`services/`) | Domain logic; no HTTP, no DB driver |
| Data access (`repositories/`) | Repository/DAO; all SQL parameterized |

It listens on `:8080` (the MIG named port and health-check port), exposes
`/healthz` (liveness — no DB) and `/readyz` (readiness — checks the DB), takes
all config from environment variables, and receives the DB password from
**Secret Manager** at deploy time. Endpoints: storefront HTML (`/`,
`/product/{id}`, `/cart`, `/checkout`) and a JSON API (`/api/products`,
`/api/categories`, `/api/cart`, `/api/checkout`, `/api/orders`,
`/api/admin/sync`). The catalog auto-syncs from FakeStore via Cloud NAT on
startup. Details in [`ecommerce-app/README.md`](ecommerce-app/README.md).

## The infrastructure

Reusable Terraform modules composed per environment, each with isolated GCS
state. Highlights:

- **Network** — custom VPC, app subnet, Private Services Access for Cloud SQL,
  Cloud Router + NAT, least-privilege firewall (IAP-only SSH, health-check and
  app-port rules). No default VPC, no public SSH.
- **Cloud SQL** — PostgreSQL on **private IP only**, password in Secret Manager.
- **Compute tier** — service account (least privilege) → instance template
  (no external IP, Shielded VM, `ecommerce-app/deploy/startup.sh`) → regional MIG
  (autoheal + **CPU autoscaling**, 2→N, rolling updates) → health checks →
  regional backend service → regional Application Load Balancer serving **HTTPS
  with an HTTP→HTTPS 301 redirect**. A firewall rule allows the ALB's
  **proxy-only subnet** to reach the app port — required for a regional Envoy LB
  to serve traffic.
- **HTTPS / DNS** — a **Google-managed TLS certificate** (Certificate Manager,
  DNS authorization) terminates at the ALB; both the validation CNAME and the
  hostname A record live in **Cloud DNS**, managed as Terraform.
- **Delivery** — a private, versioned **GCS artifact bucket** holds the app; the
  VM startup script pulls `current/` on boot.

Two health checks are used deliberately: MIG **autohealing** probes `/healthz`
(liveness — only recreate dead processes) while the **load balancer** probes
`/readyz` (readiness — only route to instances whose DB is reachable).

Full module reference and wiring in [`terraform/README.md`](terraform/README.md).

## CI/CD ([`.github/workflows/`](.github/workflows/))

- **`ci.yml`** (PR gate, no cloud creds) — Ruff + pytest the app, `terraform fmt`
  / `validate` (dev + prod), and a **Trivy** IaC security scan.
- **`deploy.yml`** (keyless, Workload Identity Federation) — push to `main`
  auto-deploys to **dev**; prod is a manual `workflow_dispatch` gated by the prod
  GitHub Environment's protection rules. It publishes a versioned artifact to the
  GCS bucket, rolls the MIG zero-downtime, waits for stability, and smoke-tests
  `/readyz` through the load balancer.

To run the deploy workflow, configure per-environment GitHub Environment secrets
(`WIF_PROVIDER`, `DEPLOY_SA`) and variables (`GCP_PROJECT_ID`, `GCP_REGION`,
optional `APP_NAME`, `APP_URL`). These come from the `github-oidc` Terraform
module outputs.

## Deploy order

The VMs pull the app from the artifact bucket **on first boot**, so publish the
app before the MIG comes up:

1. **Bootstrap** the artifact bucket + IAM:
   `terraform apply -target=module.iam -target=module.artifact_bucket`.
2. **Publish** the app to `gs://<...>-<env>-artifacts/current/` (`gsutil rsync`
   the `ecommerce-app/` tree, or run the deploy workflow).
3. `terraform apply` the rest of the stack.

## Security highlights

- Custom VPC only; application instances have **no external IP** (egress via
  Cloud NAT); Cloud SQL is **private IP only**.
- SSH only via **IAP**; never `0.0.0.0/0`. Only the load balancer takes public
  traffic.
- **Least-privilege IAM** (no owner/editor); the app SA gets `logging.logWriter`,
  `monitoring.metricWriter`, `cloudsql.client`, and secret-scoped
  `secretmanager.secretAccessor`.
- **No hardcoded secrets** — the generated DB password lives in Secret Manager.
  `terraform.tfvars` holds only non-secret env values (project ID, region, CIDRs);
  replace the placeholder `project_id` and state `bucket` with your own.

> **Note:** `terraform.tfvars` and `backend.tf` reference an example project ID
> and GCS state bucket. Replace them with your own before `terraform init`.
