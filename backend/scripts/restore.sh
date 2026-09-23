#!/usr/bin/env bash
set -euo pipefail
: "${RESTORE_DATABASE_URL:?RESTORE_DATABASE_URL must name a separate empty database}"
bp_file="${1:?Usage: restore.sh /backups/bezpieczna-YYYYMMDDTHHMMSSZ.dump}"
test -f "$bp_file" && test -f "$bp_file.sha256"
(cd "$(dirname "$bp_file")" && sha256sum --check "$(basename "$bp_file").sha256")
bp_count="$(psql "$RESTORE_DATABASE_URL" -AtX -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','p')")"
test "$bp_count" = 0 || { echo 'Restore target is not empty; refusing to overwrite' >&2; exit 1; }
pg_restore --exit-on-error --single-transaction --no-owner --no-acl --dbname="$RESTORE_DATABASE_URL" "$bp_file"
psql "$RESTORE_DATABASE_URL" -AtX -v ON_ERROR_STOP=1 -c "SELECT PostGIS_Version()" >/dev/null
echo 'Restore complete and PostGIS verified'
