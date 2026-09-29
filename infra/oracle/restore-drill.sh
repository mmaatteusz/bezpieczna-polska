#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root." >&2
  exit 1
fi

BACKUP_DIR=/var/backups/bezpieczna-polska
DUMP="${1:-}"
if [[ -z "${DUMP}" ]]; then
  DUMP="$(find "${BACKUP_DIR}" -maxdepth 1 -type f -name 'bezpieczna-polska-*.dump' -printf '%T@ %p\n' | sort -nr | head -n1 | cut -d' ' -f2-)"
fi
if [[ -z "${DUMP}" || ! -f "${DUMP}" ]]; then
  echo "No backup dump available." >&2
  exit 1
fi

if [[ -f "${DUMP}.sha256" ]]; then
  (cd "$(dirname "${DUMP}")" && sha256sum -c "$(basename "${DUMP}.sha256")")
fi
pg_restore --list "${DUMP}" >/dev/null

TEMP_DB="bp_restore_drill_$(date -u +%Y%m%d%H%M%S)"
cleanup(){
  sudo -u postgres dropdb --if-exists "${TEMP_DB}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

sudo -u postgres createdb "${TEMP_DB}"
sudo -u postgres pg_restore --no-owner --no-privileges --exit-on-error --dbname="${TEMP_DB}" "${DUMP}"

POSTGIS="$(sudo -u postgres psql -d "${TEMP_DB}" -Atqc "SELECT extversion FROM pg_extension WHERE extname='postgis'")"
test -n "${POSTGIS}"

for table in schema_migrations event_revisions incident_revisions source_health radiation_measurements shelters push_devices push_outbox worker_leases; do
  exists="$(sudo -u postgres psql -d "${TEMP_DB}" -Atqc "SELECT to_regclass('public.${table}') IS NOT NULL")"
  if [[ "${exists}" != "t" ]]; then
    echo "Restore drill missing table: ${table}" >&2
    exit 1
  fi
done

SCHEMA_VERSION="$(sudo -u postgres psql -d "${TEMP_DB}" -Atqc 'SELECT COALESCE(MAX(version),0) FROM schema_migrations')"
SOURCE_COUNT="$(sudo -u postgres psql -d "${TEMP_DB}" -Atqc 'SELECT COUNT(*) FROM source_health')"
SHELTER_COUNT="$(sudo -u postgres psql -d "${TEMP_DB}" -Atqc 'SELECT COUNT(*) FROM shelters')"

echo "RESTORE_DRILL_PASS database=${TEMP_DB} postgis=${POSTGIS} schema=${SCHEMA_VERSION} sources=${SOURCE_COUNT} shelters=${SHELTER_COUNT}"
