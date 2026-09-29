#!/usr/bin/env bash
set -euo pipefail

SOURCE_DATABASE_URL="${SOURCE_DATABASE_URL:-}"
OUTPUT="${1:-bezpieczna-polska-source-$(date -u +%Y%m%dT%H%M%SZ).dump}"

if [[ -z "${SOURCE_DATABASE_URL}" ]]; then
  echo "SOURCE_DATABASE_URL must be supplied through the environment." >&2
  exit 1
fi
if [[ "${OUTPUT}" != *.dump ]]; then
  echo "Output file must end in .dump" >&2
  exit 1
fi

umask 077
pg_dump --dbname="${SOURCE_DATABASE_URL}" --format=custom --compress=9 --no-owner --no-privileges --file="${OUTPUT}"
pg_restore --list "${OUTPUT}" >/dev/null
sha256sum "${OUTPUT}" > "${OUTPUT}.sha256"

echo "Source database export complete: ${OUTPUT}"
echo "The database URL was not written to the backup."
