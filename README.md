# Nova Store — FastAPI monolith for GCP three-tier deployment

A single-process **FastAPI monolith** folded from a polyglot microservices app
(Go catalog, Java cart/order/ui, Node checkout, Redis, multi-DB) into one
deployable backed by **one Cloud SQL PostgreSQL** database. It is drop-in
compatible with a GCP three-tier deployment (**ALB → MIG → Compute Engine →
Cloud SQL**) and the prod `deploy/startup.sh` in this repo.

> **Companion infrastructure:** the Terraform that provisions the VPC, ALB,
> Managed Instance Group, Cloud NAT, and private Cloud SQL for this app lives in
> [`gcp-three-tier-monolith-repo`](https://github.com/aslamchandio/gcp-three-tier-monolith-repo).
> This repo is the **application tier**; that repo is the **infrastructure**.

## What was merged

| Original service | Language | Folded into |
|------------------|----------|-------------|
| catalog-service  | Go       | `services/catalog_service.py` (+ background sync from FakeStore) |
| cart-service     | Java/Redis | `services/cart_service.py` (cart in Postgres, not Redis) |
| checkout-service | Node     | `services/checkout_service.py` (one in-process transaction) |
| order-service    | Java/JPA | `services/order_service` via `repositories/order_repository.py` |
| ui-service       | Java/Thymeleaf | `api/routes_storefront.py` + Jinja2 `templates/` (same Nova Store UI) |

Inter-service HTTP calls become in-process method calls; the three data stores
(catalog DB, Redis cart, orders DB) become four tables in one database:
`products`, `cart_items`, `orders`, `order_items`.

## Layered architecture (one process)

```
api/ (routes_storefront HTML + routes_api JSON + routes_health)
  -> services/ (catalog, cart, checkout)   business logic, no HTTP/SQL driver
    -> repositories/ (product, cart, order) all SQL via SQLAlchemy
      -> Cloud SQL PostgreSQL (private IP)
```

## Endpoints

- **Storefront (HTML):** `/`, `/product/{id}`, `/cart` (+ `/cart/add`, `/cart/remove`), `/checkout`
- **JSON API:** `/api/products`, `/api/products/{id}`, `/api/categories`,
  `/api/cart` (GET/POST items/DELETE), `/api/checkout`, `/api/orders`, `/api/admin/sync`
- **Ops:** `/healthz` (liveness), `/readyz` (readiness — checks DB), `/docs`

The catalog auto-syncs from `FAKESTORE_URL` on startup and every
`SYNC_INTERVAL_HOURS` (reached via Cloud NAT). Trigger manually with
`POST /api/admin/sync`.

## Configuration (env)

All configuration is read from environment variables — no hardcoded hosts,
ports, or credentials. Copy `.env.example` to `.env` for local dev; in
production the VM `startup.sh` writes these to `/etc/monolith.env` with
`DB_PASSWORD` injected from Google Secret Manager.

Key vars: `PORT`, `ENVIRONMENT`, `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`,
`DB_PASSWORD`, `DB_MAX_CONNECTIONS`, `DB_SSL_MODE`, plus `FAKESTORE_URL`,
`SYNC_INTERVAL_HOURS`, `SYNC_ON_STARTUP`. See [`.env.example`](.env.example) for
the full list and defaults.

## Run locally

```bash
python -m venv .venv && . .venv/bin/activate     # Windows: .venv\Scripts\activate
pip install -e .
cp .env.example .env                             # then edit DB_* to point at a local Postgres
export DB_HOST=127.0.0.1 DB_SSL_MODE=disable     # local plaintext dev DB
alembic upgrade head
uvicorn monolith.main:app --port 8080
# open http://localhost:8080
```

## Deploy (prod)

Published as a versioned artifact to the prod bucket and pulled by the MIG VMs:

```bash
gsutil -m rsync -r -d ./ gs://<PROJECT>-three-tier-prod-artifacts/current
gcloud compute instance-groups managed rolling-action replace three-tier-prod-mig \
  --region=us-central1 --project=<PROJECT>
```

The DB migration is chained (`0002` after `0001`), so the prod database — already
stamped at `0001` — upgrades cleanly when each new VM runs `alembic upgrade head`.
During a rolling deploy several VMs boot at once, so the migration is
**serialized by a PostgreSQL advisory lock** in `deploy/startup.sh`: the first VM
migrates while the rest block, then they run `upgrade head` as a no-op — the DB
is migrated exactly once.
