#!/usr/bin/env bash
#
# GCE instance-template startup script for the monolith.
#
# Place the contents of this file in the instance template's
# `metadata_startup_script` (Terraform: metadata_startup_script = file(...)).
# It runs on every boot of every MIG VM. The app instances have NO external IP;
# package downloads and code fetch go out via Cloud NAT, and the database is
# reached over the Cloud SQL PRIVATE IP.
#
# Flow: install runtime -> fetch code -> create venv -> write env file
#       (DB_PASSWORD from Secret Manager) -> run migrations ONCE -> start systemd.
#
set -euo pipefail

# ---- Configuration (override via instance metadata) -------------------------
# Read non-secret config from instance metadata so the same image serves any env.
METADATA="http://metadata.google.internal/computeMetadata/v1"
meta() { curl -s -H "Metadata-Flavor: Google" "${METADATA}/instance/attributes/$1"; }

APP_DIR=/opt/monolith/app
VENV_DIR=/opt/monolith/venv
ENV_FILE=/etc/monolith.env

PROJECT_ID="$(curl -s -H 'Metadata-Flavor: Google' "${METADATA}/project/project-id")"
ENVIRONMENT="$(meta environment || echo production)"
DB_HOST="$(meta db_host)"                       # Cloud SQL PRIVATE IP, e.g. 10.77.0.2
DB_PORT="$(meta db_port || echo 5432)"
DB_NAME="$(meta db_name || echo appdb)"
DB_USER="$(meta db_user || echo appuser)"
DB_SECRET_ID="$(meta db_password_secret_id)"    # e.g. three-tier-prod-db-password
DB_MAX_CONNECTIONS="$(meta db_max_connections || echo 10)"
APP_PORT="$(meta app_port || echo 8080)"
CODE_BUCKET="$(meta code_bucket || echo '')"    # gs://... artifact location (optional)

# ---- 1. Install runtime -----------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y python3 python3-venv python3-pip git curl postgresql-client

id -u appuser >/dev/null 2>&1 || useradd --system --create-home --shell /usr/sbin/nologin appuser

# ---- 2. Fetch application code ----------------------------------------------
# gsutil rsync needs the local destination directory to already exist.
mkdir -p "${APP_DIR}"
if [[ -n "${CODE_BUCKET}" ]]; then
  # Production: pull a versioned artifact from GCS (private, via Cloud NAT/PGA).
  gsutil -m rsync -r "${CODE_BUCKET}" "${APP_DIR}"
else
  # Fallback for demos: clone from a git repo metadata key `repo_url`.
  REPO_URL="$(meta repo_url || echo '')"
  if [[ -n "${REPO_URL}" ]]; then
    rm -rf "${APP_DIR}"
    git clone --depth 1 "${REPO_URL}" "${APP_DIR}"
  fi
fi
chown -R appuser:appuser /opt/monolith

# ---- 3. Python virtualenv + dependencies ------------------------------------
python3 -m venv "${VENV_DIR}"
"${VENV_DIR}/bin/pip" install --upgrade pip
"${VENV_DIR}/bin/pip" install -e "${APP_DIR}"

# ---- 4. Fetch the DB password from Secret Manager ---------------------------
# The VM service account needs roles/secretmanager.secretAccessor on the secret.
DB_PASSWORD="$(gcloud secrets versions access latest \
  --secret="${DB_SECRET_ID}" --project="${PROJECT_ID}")"

# ---- 5. Write the environment file (root-owned, not world-readable) ---------
umask 027
# Single-quote the password: it may contain shell-special characters, and both
# `source` (bash) and systemd's EnvironmentFile read single-quoted values
# literally. The generated password contains no single-quote, so this is safe.
cat > "${ENV_FILE}" <<EOF
PORT=${APP_PORT}
ENVIRONMENT=${ENVIRONMENT}
LOG_LEVEL=INFO
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD='${DB_PASSWORD}'
DB_MAX_CONNECTIONS=${DB_MAX_CONNECTIONS}
EOF
chmod 0640 "${ENV_FILE}"
chown root:appuser "${ENV_FILE}"

# ---- 6. Run database migrations ONCE, serialized across instances -----------
# Every MIG VM runs this on boot, and a rolling deploy surges several VMs at
# once — so without coordination they would all `alembic upgrade head` the same
# database concurrently and race on a new migration. A PostgreSQL session-level
# advisory lock serializes them: the first VM acquires the lock and migrates;
# the others BLOCK at pg_advisory_lock until it is released, then run their own
# `upgrade head` as a clean no-op.
#
# The lock is held inside ONE psql session for the whole migration — alembic is
# launched from that session via psql's \!, so the session (and the lock) stay
# open until alembic returns, and the lock auto-releases if this VM dies
# mid-migration. ON_ERROR_STOP doesn't fire on \! failures, so we capture
# alembic's own exit code and fail the boot if the migration failed.
set -a; source "${ENV_FILE}"; set +a

MIGRATION_LOCK_KEY=727274            # arbitrary; must be identical on every VM
MIG_STATUS_FILE="$(mktemp)"
export PGPASSWORD="${DB_PASSWORD}"
export PGSSLMODE=require              # Cloud SQL is ssl_mode = ENCRYPTED_ONLY

psql -v ON_ERROR_STOP=1 \
  -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" <<SQL
SET lock_timeout = '300s';
SELECT pg_advisory_lock(${MIGRATION_LOCK_KEY});
\! sh -c 'cd "${APP_DIR}" && "${VENV_DIR}/bin/alembic" upgrade head'; echo \$? > "${MIG_STATUS_FILE}"
SELECT pg_advisory_unlock(${MIGRATION_LOCK_KEY});
SQL

MIG_RC="$(cat "${MIG_STATUS_FILE}" 2>/dev/null || echo 1)"
rm -f "${MIG_STATUS_FILE}"
unset PGPASSWORD
if [ "${MIG_RC}" != "0" ]; then
  echo "database migration failed (alembic exit ${MIG_RC})" >&2
  exit 1
fi

# ---- 7. Install & start the systemd service ---------------------------------
cp "${APP_DIR}/deploy/monolith.service" /etc/systemd/system/monolith.service
systemctl daemon-reload
systemctl enable monolith.service
systemctl restart monolith.service

echo "monolith startup complete"
