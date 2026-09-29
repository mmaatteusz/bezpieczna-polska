#!/usr/bin/env bash
set -euo pipefail

fail(){ echo "AUDIT_FAIL $*" >&2; exit 1; }
pass(){ echo "AUDIT_OK $*"; }
warn(){ echo "AUDIT_WARN $*" >&2; }

source /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || fail "expected Ubuntu, got ${ID:-unknown}"
pass "os=ubuntu version=${VERSION_ID:-unknown}"

ARCH="$(dpkg --print-architecture)"
[[ "${ARCH}" == "arm64" ]] || fail "expected arm64, got ${ARCH}"
pass "architecture=arm64"

CPU_COUNT="$(nproc)"
(( CPU_COUNT >= 1 )) || fail "less than 1 CPU available"
pass "cpus=${CPU_COUNT}"

MEM_KB="$(awk '/MemTotal:/ {print $2}' /proc/meminfo)"
(( MEM_KB >= 3145728 )) || fail "less than 3 GiB RAM available"
pass "memory_mib=$((MEM_KB/1024))"

ROOT_BYTES="$(df -B1 --output=size / | tail -n1 | tr -d ' ')"
(( ROOT_BYTES >= 64424509440 )) || fail "root filesystem smaller than 60 GiB"
pass "root_disk_gib=$((ROOT_BYTES/1024/1024/1024))"

for cmd in docker nginx psql pg_dump pg_restore jq curl ss; do
  command -v "${cmd}" >/dev/null 2>&1 || fail "missing command: ${cmd}"
done
pass "required_commands_present"

PSQL_VERSION="$(psql --version | awk '{print $3}')"
[[ "${PSQL_VERSION}" == 17.* ]] || fail "expected PostgreSQL client 17, got ${PSQL_VERSION}"
pass "postgres_client=${PSQL_VERSION}"

for service in docker nginx postgresql; do
  systemctl is-active --quiet "${service}" || fail "service not active: ${service}"
  pass "service_active=${service}"
done

PG_LISTEN="$(sudo -u postgres psql -Atqc 'SHOW listen_addresses')"
[[ "${PG_LISTEN}" == "127.0.0.1" ]] || fail "PostgreSQL listen_addresses is ${PG_LISTEN}, expected 127.0.0.1"
pass "postgres_listen=127.0.0.1"

POSTGIS_PACKAGE="$(dpkg-query -W -f='${Status}' postgresql-17-postgis-3 2>/dev/null || true)"
[[ "${POSTGIS_PACKAGE}" == "install ok installed" ]] || fail "postgresql-17-postgis-3 package not installed"
pass "postgis_package_installed"

if ss -ltnH | awk '{print $4}' | grep -Eq '(^|:)0\.0\.0\.0:5432$|^\[::\]:5432$|(^|:)0\.0\.0\.0:8080$|^\[::\]:8080$'; then
  fail "database or API is listening on a public wildcard address"
fi
pass "private_ports_not_public"

UFW_STATE="$(ufw status | head -n1)"
[[ "${UFW_STATE}" == "Status: active" ]] || fail "UFW is not active"
pass "ufw_active"

nginx -t >/dev/null 2>&1 || fail "nginx configuration invalid"
pass "nginx_configuration_valid"

systemctl is-enabled --quiet bezpieczna-polska-backup.timer || fail "backup timer not enabled"
pass "backup_timer_enabled"

ENV_FILE=/etc/bezpieczna-polska/backend.env
if [[ -f "${ENV_FILE}" ]]; then
  MODE="$(stat -c '%a' "${ENV_FILE}")"
  [[ "${MODE}" == "600" ]] || fail "backend.env must have mode 600, got ${MODE}"
  for key in APP_ENV NODE_ENV HOST PORT TRUST_PROXY PUBLIC_BASE_URL DATABASE_URL ADMIN_TOKEN; do
    grep -q "^${key}=." "${ENV_FILE}" || fail "backend.env missing ${key}"
  done
  grep -q '^APP_ENV=production$' "${ENV_FILE}" || fail "APP_ENV must be production"
  grep -q '^NODE_ENV=production$' "${ENV_FILE}" || fail "NODE_ENV must be production"
  grep -q '^HOST=127.0.0.1$' "${ENV_FILE}" || fail "HOST must be 127.0.0.1"
  grep -q '^TRUST_PROXY=true$' "${ENV_FILE}" || fail "TRUST_PROXY must be true"
  if grep -Eq 'CHANGE_ME|example\.pl' "${ENV_FILE}"; then
    fail "backend.env still contains placeholder values"
  fi
  pass "backend_env_secure"
else
  warn "backend.env not present yet; runtime checks skipped"
fi

if systemctl is-active --quiet bezpieczna-polska-api.service; then
  RELEASE_SHA="$(sed -n 's/^BUILD_SHA=//p' /opt/bezpieczna-polska/release.env 2>/dev/null | head -n1)"
  [[ "${RELEASE_SHA}" =~ ^[a-f0-9]{40}$ ]] || fail "release.env missing valid BUILD_SHA"
  HEALTH="$(curl -fsS --max-time 5 http://127.0.0.1:8080/health)" || fail "local /health unavailable"
  READY="$(curl -fsS --max-time 5 http://127.0.0.1:8080/ready)" || fail "local /ready unavailable"
  jq -e --arg sha "${RELEASE_SHA}" '.buildSha == $sha and .environment == "production"' <<<"${HEALTH}" >/dev/null ||
    fail "health identity does not match release SHA"
  jq -e '.ready == true and .database == "postgres" and .postgis == true' <<<"${READY}" >/dev/null ||
    fail "ready/PostGIS contract failed"
  pass "api_runtime_healthy build_sha=${RELEASE_SHA}"
else
  warn "API service not active yet; runtime checks skipped"
fi

echo "ORACLE_HOST_AUDIT_PASS"
