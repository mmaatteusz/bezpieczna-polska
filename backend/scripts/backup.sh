#!/usr/bin/env bash
set -euo pipefail
: "${DATABASE_URL:?DATABASE_URL is required}"
bp_dir="${BACKUP_DIR:-/backups}"
bp_days="${BACKUP_KEEP_DAYS:-14}"
[[ "$bp_days" =~ ^[1-9][0-9]*$ ]] || { echo 'Invalid retention' >&2; exit 1; }
umask 077
mkdir -p "$bp_dir"
bp_tmp="$(mktemp "$bp_dir/.backup.XXXXXXXX")"
trap 'rm -f "$bp_tmp"' EXIT
pg_dump --dbname="$DATABASE_URL" --format=custom --compress=6 --file="$bp_tmp"
bp_file="$bp_dir/bezpieczna-$(date -u +%Y%m%dT%H%M%SZ).dump"
mv -n "$bp_tmp" "$bp_file"
(cd "$bp_dir" && sha256sum "$(basename "$bp_file")" > "$(basename "$bp_file").sha256")
find "$bp_dir" -maxdepth 1 -type f \( -name 'bezpieczna-*.dump' -o -name 'bezpieczna-*.dump.sha256' \) -mtime +"$bp_days" -delete
echo "Backup saved: $(basename "$bp_file")"
