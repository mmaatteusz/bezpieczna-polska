#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root." >&2
  exit 1
fi

DB_NAME="${BP_DB_NAME:-bezpieczna_polska}"
DB_USER="${BP_DB_USER:-bp_app}"
DB_PASSWORD="${BP_DB_PASSWORD:-}"

if [[ ! "${DB_NAME}" =~ ^[a-zA-Z0-9_]+$ || ! "${DB_USER}" =~ ^[a-zA-Z0-9_]+$ ]]; then
  echo "Database/user names may contain only letters, numbers and underscore." >&2
  exit 1
fi
if [[ ${#DB_PASSWORD} -lt 24 ]]; then
  echo "BP_DB_PASSWORD must contain at least 24 characters." >&2
  exit 1
fi

PG_CONF="/etc/postgresql/17/main/postgresql.conf"
PG_HBA="/etc/postgresql/17/main/pg_hba.conf"
test -f "${PG_CONF}" && test -f "${PG_HBA}"

sed -ri "s/^[#[:space:]]*listen_addresses[[:space:]]*=.*/listen_addresses = '127.0.0.1'/" "${PG_CONF}"
if ! grep -Eq "^host[[:space:]]+${DB_NAME}[[:space:]]+${DB_USER}[[:space:]]+127\.0\.0\.1/32[[:space:]]+scram-sha-256" "${PG_HBA}"; then
  sed -i "1ihost ${DB_NAME} ${DB_USER} 127.0.0.1/32 scram-sha-256" "${PG_HBA}"
fi
systemctl restart postgresql

SAFE_PASSWORD="${DB_PASSWORD//\'/\'\'}"
if ! sudo -u postgres psql -Atqc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -qx 1; then
  sudo -u postgres createuser --login "${DB_USER}"
fi
sudo -u postgres psql -v ON_ERROR_STOP=1 -c "ALTER ROLE \"${DB_USER}\" WITH LOGIN PASSWORD '${SAFE_PASSWORD}';"

if ! sudo -u postgres psql -Atqc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -qx 1; then
  sudo -u postgres createdb --owner="${DB_USER}" "${DB_NAME}"
fi

sudo -u postgres psql -v ON_ERROR_STOP=1 -d "${DB_NAME}" -c "CREATE EXTENSION IF NOT EXISTS postgis;"
sudo -u postgres psql -v ON_ERROR_STOP=1 -d "${DB_NAME}" -c "ALTER DATABASE \"${DB_NAME}\" SET timezone TO 'UTC';"

if ss -ltn | grep -Eq '(^|[[:space:]])0\.0\.0\.0:5432|\[::\]:5432'; then
  echo "PostgreSQL is listening publicly; refusing configuration." >&2
  exit 1
fi

echo "Database configured on 127.0.0.1:5432."
echo "Use a URL-encoded password when creating DATABASE_URL in backend.env."
