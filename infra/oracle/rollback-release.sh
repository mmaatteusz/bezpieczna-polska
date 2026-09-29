#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run through sudo/root." >&2
  exit 1
fi

SHA="${1:-}"
ROOT=/opt/bezpieczna-polska
SERVICE=bezpieczna-polska-api.service

if [[ ! "${SHA}" =~ ^[a-f0-9]{40}$ ]]; then
  echo "Usage: $0 <40-char-sha>" >&2
  exit 1
fi
if ! docker image inspect "bp-api:${SHA}" >/dev/null 2>&1; then
  echo "Image bp-api:${SHA} is not available locally." >&2
  exit 1
fi

PREVIOUS=""
if [[ -f "${ROOT}/release.env" ]]; then
  PREVIOUS="$(sed -n 's/^BUILD_SHA=//p' "${ROOT}/release.env" | head -n1)"
fi

printf 'BUILD_SHA=%s\n' "${SHA}" > "${ROOT}/release.env.tmp"
chmod 0644 "${ROOT}/release.env.tmp"
mv "${ROOT}/release.env.tmp" "${ROOT}/release.env"

systemctl restart "${SERVICE}"

for _ in $(seq 1 30); do
  if health="$(curl -fsS --max-time 3 http://127.0.0.1:8080/health 2>/dev/null)" &&
     ready="$(curl -fsS --max-time 3 http://127.0.0.1:8080/ready 2>/dev/null)" &&
     jq -e --arg sha "${SHA}" '.buildSha == $sha and .environment == "production"' <<<"${health}" >/dev/null &&
     jq -e '.ready == true and .database == "postgres" and .postgis == true' <<<"${ready}" >/dev/null; then
    echo "Rollback target healthy: ${SHA}"
    exit 0
  fi
  sleep 2
done

echo "Rollback target failed health checks." >&2
if [[ "${PREVIOUS}" =~ ^[a-f0-9]{40}$ ]] && docker image inspect "bp-api:${PREVIOUS}" >/dev/null 2>&1; then
  printf 'BUILD_SHA=%s\n' "${PREVIOUS}" > "${ROOT}/release.env"
  systemctl restart "${SERVICE}"
  echo "Restored previous runtime image ${PREVIOUS}. Database migrations are never reverted automatically." >&2
fi
exit 1
