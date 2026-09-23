#!/usr/bin/env bash
set -euo pipefail
: "${TEST_DATABASE_URL:?TEST_DATABASE_URL required}"
bp_root="${TEST_DATABASE_URL%/*}"
bp_admin="$TEST_DATABASE_URL"
bp_source="$bp_root/backup_source"
bp_target="$bp_root/backup_target"
psql "$bp_admin" -v ON_ERROR_STOP=1 -c 'CREATE DATABASE backup_source'
psql "$bp_admin" -v ON_ERROR_STOP=1 -c 'CREATE DATABASE backup_target'
psql "$bp_source" -v ON_ERROR_STOP=1 -c "CREATE EXTENSION postgis; CREATE TABLE source_health(id text PRIMARY KEY,payload text NOT NULL); INSERT INTO source_health VALUES('RESTORE_SENTINEL','{\"lastSuccess\":\"2026-09-23T00:00:00Z\",\"value\":\"alpha16\"}');"
bp_out="$(mktemp -d)"
trap 'rm -rf "$bp_out"' EXIT
DATABASE_URL="$bp_source" BACKUP_DIR="$bp_out" bash backend/scripts/backup.sh
bp_dump="$(find "$bp_out" -name '*.dump' -print -quit)"
RESTORE_DATABASE_URL="$bp_target" bash backend/scripts/restore.sh "$bp_dump"
bp_actual="$(psql "$bp_target" -AtX -v ON_ERROR_STOP=1 -c "SELECT payload::jsonb->>'value' FROM source_health WHERE id='RESTORE_SENTINEL'")"
test "$bp_actual" = alpha16 || { echo 'Restore data mismatch' >&2; exit 1; }
echo 'Backup restore smoke: actual seeded row and PostGIS PASS'
