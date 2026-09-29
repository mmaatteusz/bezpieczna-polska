#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root." >&2
  exit 1
fi

DOMAIN="${1:-}"
EMAIL="${2:-}"
if [[ ! "${DOMAIN}" =~ ^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
  echo "Usage: $0 api.example.pl admin@example.pl" >&2
  exit 1
fi
if [[ ! "${EMAIL}" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; then
  echo "Valid email required for Let's Encrypt." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="/etc/nginx/sites-available/bezpieczna-polska-api"

sed "s/__API_DOMAIN__/${DOMAIN}/g" "${SCRIPT_DIR}/nginx.conf.template" > "${TARGET}"
ln -sfn "${TARGET}" /etc/nginx/sites-enabled/bezpieczna-polska-api
rm -f /etc/nginx/sites-enabled/default

nginx -t
systemctl reload nginx

certbot --nginx --non-interactive --agree-tos --redirect --email "${EMAIL}" -d "${DOMAIN}"
nginx -t
systemctl reload nginx

echo "HTTPS enabled for https://${DOMAIN}"
