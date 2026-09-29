#!/usr/bin/env bash
set -euo pipefail

SOURCE_DATABASE_URL="${SOURCE_DATABASE_URL:-}"
TARGET_DATABASE_URL="${TARGET_DATABASE_URL:-}"
STRICT="${BP_STRICT_COUNTS:-NO}"

[[ -n "${SOURCE_DATABASE_URL}" ]] || { echo "SOURCE_DATABASE_URL is required" >&2; exit 1; }
[[ -n "${TARGET_DATABASE_URL}" ]] || { echo "TARGET_DATABASE_URL is required" >&2; exit 1; }
[[ "${STRICT}" == "YES" || "${STRICT}" == "NO" ]] || { echo "BP_STRICT_COUNTS must be YES or NO" >&2; exit 1; }

tables=(
  schema_migrations
  event_revisions
  incident_revisions
  source_health
  neptun_track_revisions
  radiation_measurements
  shelters
  push_devices
  push_outbox
  worker_leases
)

query(){
  local url="$1"
  local sql="$2"
  psql "$url" -v ON_ERROR_STOP=1 -Atqc "$sql"
}

source_schema="$(query "$SOURCE_DATABASE_URL" 'SELECT COALESCE(MAX(version),0) FROM schema_migrations')"
target_schema="$(query "$TARGET_DATABASE_URL" 'SELECT COALESCE(MAX(version),0) FROM schema_migrations')"
[[ "$source_schema" == "$target_schema" ]] || { echo "SCHEMA_MISMATCH source=$source_schema target=$target_schema" >&2; exit 1; }

source_postgis="$(query "$SOURCE_DATABASE_URL" "SELECT extversion FROM pg_extension WHERE extname='postgis'")"
target_postgis="$(query "$TARGET_DATABASE_URL" "SELECT extversion FROM pg_extension WHERE extname='postgis'")"
[[ -n "$source_postgis" && -n "$target_postgis" ]] || { echo "POSTGIS_MISSING" >&2; exit 1; }

echo "DB_COMPARE_SCHEMA_OK version=$source_schema source_postgis=$source_postgis target_postgis=$target_postgis"

mismatch=0
for table in "${tables[@]}"; do
  source_exists="$(query "$SOURCE_DATABASE_URL" "SELECT to_regclass('public.$table') IS NOT NULL")"
  target_exists="$(query "$TARGET_DATABASE_URL" "SELECT to_regclass('public.$table') IS NOT NULL")"
  [[ "$source_exists" == "t" && "$target_exists" == "t" ]] || {
    echo "TABLE_MISSING table=$table source=$source_exists target=$target_exists" >&2
    exit 1
  }

  source_count="$(query "$SOURCE_DATABASE_URL" "SELECT COUNT(*) FROM $table")"
  target_count="$(query "$TARGET_DATABASE_URL" "SELECT COUNT(*) FROM $table")"
  delta=$((target_count-source_count))
  echo "DB_COMPARE_COUNT table=$table source=$source_count target=$target_count delta=$delta"
  if [[ "$source_count" != "$target_count" ]]; then
    mismatch=1
  fi
done

if [[ "$mismatch" -eq 1 ]]; then
  if [[ "$STRICT" == "YES" ]]; then
    echo "DB_COMPARE_FAIL count mismatch in strict mode" >&2
    exit 1
  fi
  echo "DB_COMPARE_WARN row counts differ; source may have advanced after the dump" >&2
fi

echo "DB_COMPARE_PASS strict=$STRICT"
