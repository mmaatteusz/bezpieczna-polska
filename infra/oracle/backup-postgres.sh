#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root." >&2
  exit 1
fi

ENV_FILE=/etc/bezpieczna-polska/backend.env
BACKUP_DIR=/var/backups/bezpieczna-polska
RETENTION_DAYS="${BP_BACKUP_RETENTION_DAYS:-14}"
UPLOAD_HOOK=/usr/local/sbin/bp-backup-upload

test -f "${ENV_FILE}"
DATABASE_URL="$(grep -m1 '^DATABASE_URL=' "${ENV_FILE}" | cut -d= -f2-)"
if [[ -z "${DATABASE_URL}" ]]; then
  echo "DATABASE_URL missing from backend.env" >&2
  exit 1
fi
if [[ ! "${RETENTION_DAYS}" =~ ^[0-9]+$ || "${RETENTION_DAYS}" -lt 2 ]]; then
  echo "BP_BACKUP_RETENTION_DAYS must be an integer >= 2." >&2
  exit 1
fi

install -d -m 0700 "${BACKUP_DIR}"
umask 077
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
DUMP="${BACKUP_DIR}/bezpieczna-polska-${STAMP}.dump"
META="${DUMP}.json"

pg_dump --dbname="${DATABASE_URL}" --format=custom --compress=9 --no-owner --no-privileges --file="${DUMP}"
pg_restore --list "${DUMP}" >/dev/null
sha256sum "${DUMP}" > "${DUMP}.sha256"

SERVER_VERSION="$(psql "${DATABASE_URL}" -Atqc 'SHOW server_version')"
POSTGIS_VERSION="$(psql "${DATABASE_URL}" -Atqc "SELECT extversion FROM pg_extension WHERE extname='postgis'")"
SCHEMA_VERSION="$(psql "${DATABASE_URL}" -Atqc 'SELECT COALESCE(MAX(version),0) FROM schema_migrations')"
SOURCE_COUNT="$(psql "${DATABASE_URL}" -Atqc 'SELECT COUNT(*) FROM source_health')"
SHELTER_COUNT="$(psql "${DATABASE_URL}" -Atqc 'SELECT COUNT(*) FROM shelters')"

jq -n   --arg createdAt "$(date -u +%FT%TZ)"   --arg serverVersion "${SERVER_VERSION}"   --arg postgisVersion "${POSTGIS_VERSION}"   --arg schemaVersion "${SCHEMA_VERSION}"   --arg sourceCount "${SOURCE_COUNT}"   --arg shelterCount "${SHELTER_COUNT}"   '{createdAt:$createdAt,serverVersion:$serverVersion,postgisVersion:$postgisVersion,schemaVersion:$schemaVersion,sourceCount:$sourceCount,shelterCount:$shelterCount}'   > "${META}"

if [[ -x "${UPLOAD_HOOK}" ]]; then
  "${UPLOAD_HOOK}" "${DUMP}" "${DUMP}.sha256" "${META}"
else
  echo "No off-VM upload hook installed yet; local backup only." >&2
fi

find "${BACKUP_DIR}" -type f -name 'bezpieczna-polska-*.dump' -mtime "+${RETENTION_DAYS}" -print0 |
  while IFS= read -r -d '' old; do
    rm -f "${old}" "${old}.sha256" "${old}.json"
  done

echo "Backup complete: ${DUMP}"
