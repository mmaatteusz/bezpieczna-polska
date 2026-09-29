#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root." >&2
  exit 1
fi

DUMP="${1:-}"
DB_NAME="${BP_DB_NAME:-bezpieczna_polska}"
DB_USER="${BP_DB_USER:-bp_app}"

if [[ "${BP_ALLOW_DESTRUCTIVE_RESTORE:-}" != "YES" ]]; then
  echo "Refusing destructive restore. Set BP_ALLOW_DESTRUCTIVE_RESTORE=YES explicitly." >&2
  exit 1
fi
if [[ -z "${DUMP}" || ! -f "${DUMP}" ]]; then
  echo "Usage: BP_ALLOW_DESTRUCTIVE_RESTORE=YES $0 <source.dump>" >&2
  exit 1
fi
if [[ ! "${DB_NAME}" =~ ^[a-zA-Z0-9_]+$ || ! "${DB_USER}" =~ ^[a-zA-Z0-9_]+$ ]]; then
  echo "Invalid database/user name." >&2
  exit 1
fi
if [[ "${DB_NAME}" == "postgres" || "${DB_NAME}" == template* ]]; then
  echo "Refusing to restore into a system database." >&2
  exit 1
fi
if ! sudo -u postgres psql -Atqc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -qx 1; then
  echo "Role ${DB_USER} does not exist. Run configure-database.sh first." >&2
  exit 1
fi

if [[ -f "${DUMP}.sha256" ]]; then
  (cd "$(dirname "${DUMP}")" && sha256sum -c "$(basename "${DUMP}.sha256")")
fi
pg_restore --list "${DUMP}" >/dev/null

WAS_ACTIVE=false
if systemctl is-active --quiet bezpieczna-polska-api.service; then
  WAS_ACTIVE=true
  systemctl stop bezpieczna-polska-api.service
fi

TOC="$(mktemp)"
trap 'rm -f "${TOC}"' EXIT
pg_restore --list "${DUMP}" |
  grep -Ev '[[:space:]]EXTENSION[[:space:]]+-[[:space:]]+postgis([[:space:]]|$)|[[:space:]]COMMENT[[:space:]]+-[[:space:]]+EXTENSION[[:space:]]+postgis([[:space:]]|$)'   > "${TOC}"

sudo -u postgres dropdb --if-exists "${DB_NAME}"
sudo -u postgres createdb --owner="${DB_USER}" "${DB_NAME}"
sudo -u postgres psql -v ON_ERROR_STOP=1 -d "${DB_NAME}" -c 'CREATE EXTENSION postgis;'

sudo -u postgres pg_restore   --role="${DB_USER}"   --no-owner   --no-privileges   --exit-on-error   --use-list="${TOC}"   --dbname="${DB_NAME}"   "${DUMP}"

POSTGIS="$(sudo -u postgres psql -d "${DB_NAME}" -Atqc "SELECT extversion FROM pg_extension WHERE extname='postgis'")"
SCHEMA_VERSION="$(sudo -u postgres psql -d "${DB_NAME}" -Atqc 'SELECT COALESCE(MAX(version),0) FROM schema_migrations')"
SOURCE_COUNT="$(sudo -u postgres psql -d "${DB_NAME}" -Atqc 'SELECT COUNT(*) FROM source_health')"
SHELTER_COUNT="$(sudo -u postgres psql -d "${DB_NAME}" -Atqc 'SELECT COUNT(*) FROM shelters')"
test -n "${POSTGIS}"
test "${SCHEMA_VERSION}" -gt 0

echo "SOURCE_RESTORE_PASS postgis=${POSTGIS} schema=${SCHEMA_VERSION} sources=${SOURCE_COUNT} shelters=${SHELTER_COUNT}"

if [[ "${WAS_ACTIVE}" == true ]]; then
  systemctl start bezpieczna-polska-api.service
fi
