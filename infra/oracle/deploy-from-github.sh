#!/usr/bin/env bash
# Run on the existing Oracle VM, using its installed deployment helper.
set -euo pipefail

release_sha="${1:?Usage: bash deploy-from-github.sh EXACT_MAIN_SHA}"
[[ "$release_sha" =~ ^[a-f0-9]{40}$ ]] || { echo 'Expected an exact lowercase commit SHA.' >&2; exit 1; }
deploy_helper='/usr/local/sbin/bp-deploy-release'
test -x "$deploy_helper" || { echo 'Run this script on the existing Oracle VM.' >&2; exit 1; }
sudo -n true
work_dir="$(mktemp -d /tmp/bp-release.XXXXXX)"
trap 'rm -rf -- "$work_dir"' EXIT
curl --fail --silent --show-error --location --connect-timeout 15 --max-time 120 \
  "https://codeload.github.com/mmaatteusz/bezpieczna-polska/tar.gz/${release_sha}" \
  -o "$work_dir/source.tgz"
mkdir "$work_dir/source"
tar -xzf "$work_dir/source.tgz" --strip-components=1 -C "$work_dir/source"
tar -czf "$work_dir/release.tgz" -C "$work_dir/source" backend infra/oracle
sudo -n "$deploy_helper" "$release_sha" "$work_dir/release.tgz"
api_base='https://bezpieczna-polska-api.duckdns.org'
curl --fail --silent --show-error --max-time 15 "$api_base/health" -o "$work_dir/health.json"
curl --fail --silent --show-error --max-time 15 "$api_base/ready" -o "$work_dir/ready.json"
python3 - "$work_dir/health.json" "$work_dir/ready.json" "$release_sha" "$work_dir/source/backend/package.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f: health = json.load(f)
with open(sys.argv[2]) as f: ready = json.load(f)
with open(sys.argv[4]) as f: package = json.load(f)
assert health.get('ok') is True and health.get('environment') == 'production'
assert health.get('buildSha') == sys.argv[3], 'Backend commit mismatch'
assert health.get('version') == package['version'], 'Backend version mismatch'
assert ready.get('ready') is True and ready.get('database') == 'postgres' and ready.get('postgis') is True
print('ORACLE_DEPLOY_PASS:', health['version'], health['buildSha'])
PY
