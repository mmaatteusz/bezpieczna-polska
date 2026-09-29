#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run through sudo/root." >&2
  exit 1
fi

SHA="${1:-}"
ARCHIVE="${2:-}"
ROOT=/opt/bezpieczna-polska
ENV_FILE=/etc/bezpieczna-polska/backend.env
SERVICE=bezpieczna-polska-api.service

if [[ ! "${SHA}" =~ ^[a-f0-9]{40}$ ]]; then
  echo "First argument must be a 40-character lowercase git SHA." >&2
  exit 1
fi
if [[ ! -f "${ARCHIVE}" ]]; then
  echo "Release archive not found: ${ARCHIVE}" >&2
  exit 1
fi
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}" >&2
  exit 1
fi
chmod 600 "${ENV_FILE}"

for key in APP_ENV NODE_ENV PUBLIC_BASE_URL DATABASE_URL ADMIN_TOKEN TRUST_PROXY; do
  if ! grep -q "^${key}=." "${ENV_FILE}"; then
    echo "Missing required ${key} in backend.env" >&2
    exit 1
  fi
done

TMP="${ROOT}/releases/.${SHA}.tmp"
RELEASE="${ROOT}/releases/${SHA}"
rm -rf "${TMP}"
mkdir -p "${TMP}"
tar -xzf "${ARCHIVE}" -C "${TMP}"
test -f "${TMP}/backend/Dockerfile"
test -f "${TMP}/backend/package-lock.json"

docker build --pull -t "bp-api:${SHA}" "${TMP}/backend"

docker run --rm --network host   --env-file "${ENV_FILE}"   -e "BUILD_SHA=${SHA}"   "bp-api:${SHA}" node dist/migrate.js

rm -rf "${RELEASE}"
mv "${TMP}" "${RELEASE}"

PREVIOUS=""
if [[ -f "${ROOT}/release.env" ]]; then
  PREVIOUS="$(sed -n 's/^BUILD_SHA=//p' "${ROOT}/release.env" | head -n1)"
fi

printf 'BUILD_SHA=%s\n' "${SHA}" > "${ROOT}/release.env.tmp"
chmod 0644 "${ROOT}/release.env.tmp"
mv "${ROOT}/release.env.tmp" "${ROOT}/release.env"

systemctl daemon-reload
systemctl enable "${SERVICE}" >/dev/null
systemctl restart "${SERVICE}"

healthy=false
for _ in $(seq 1 30); do
  if health="$(curl -fsS --max-time 3 http://127.0.0.1:8080/health 2>/dev/null)" &&
     ready="$(curl -fsS --max-time 3 http://127.0.0.1:8080/ready 2>/dev/null)" &&
     jq -e --arg sha "${SHA}" '.buildSha == $sha and .environment == "production"' <<<"${health}" >/dev/null &&
     jq -e '.ready == true and .database == "postgres" and .postgis == true' <<<"${ready}" >/dev/null; then
    healthy=true
    break
  fi
  sleep 2
done

if [[ "${healthy}" != true ]]; then
  echo "New release failed local health checks." >&2
  journalctl -u "${SERVICE}" -n 80 --no-pager >&2 || true
  if [[ "${PREVIOUS}" =~ ^[a-f0-9]{40}$ ]] && docker image inspect "bp-api:${PREVIOUS}" >/dev/null 2>&1; then
    printf 'BUILD_SHA=%s\n' "${PREVIOUS}" > "${ROOT}/release.env"
    systemctl restart "${SERVICE}"
    echo "Rolled back service to ${PREVIOUS}. Database migrations are not reverted automatically." >&2
  fi
  exit 1
fi

rm -f "${ARCHIVE}"
echo "Oracle candidate release healthy: ${SHA}"
