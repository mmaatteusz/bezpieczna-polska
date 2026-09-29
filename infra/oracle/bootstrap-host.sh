#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root: sudo BP_DEPLOY_USER=ubuntu bash $0" >&2
  exit 1
fi

source /etc/os-release
if [[ "${ID}" != "ubuntu" ]]; then
  echo "This bootstrap is intentionally limited to Ubuntu." >&2
  exit 1
fi

ARCH="$(dpkg --print-architecture)"
if [[ "${ARCH}" != "arm64" ]]; then
  echo "Expected ARM64 host, got ${ARCH}." >&2
  exit 1
fi

CODENAME="${VERSION_CODENAME:-}"
if [[ -z "${CODENAME}" ]]; then
  echo "Ubuntu VERSION_CODENAME is missing." >&2
  exit 1
fi

DEPLOY_USER="${BP_DEPLOY_USER:-${SUDO_USER:-ubuntu}}"
if ! id "${DEPLOY_USER}" >/dev/null 2>&1; then
  echo "Deploy user ${DEPLOY_USER} does not exist." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl gnupg nginx certbot python3-certbot-nginx docker.io ufw jq postgresql-common

install -d -m 0755 /usr/share/postgresql-common/pgdg
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc |
  gpg --dearmor --yes -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.gpg
echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.gpg] https://apt.postgresql.org/pub/repos/apt ${CODENAME}-pgdg main"   > /etc/apt/sources.list.d/pgdg.list

apt-get update
apt-get install -y postgresql-17 postgresql-client-17 postgresql-17-postgis-3 postgresql-17-postgis-3-scripts

systemctl enable --now postgresql
systemctl enable --now docker
systemctl enable --now nginx

usermod -aG docker "${DEPLOY_USER}"

install -d -m 0750 -o root -g root /etc/bezpieczna-polska
install -d -m 0755 -o root -g root /opt/bezpieczna-polska
install -d -m 0755 -o root -g root /opt/bezpieczna-polska/releases
install -d -m 0700 -o root -g root /var/backups/bezpieczna-polska

install -m 0755 "${SCRIPT_DIR}/deploy-release.sh" /usr/local/sbin/bp-deploy-release
install -m 0755 "${SCRIPT_DIR}/rollback-release.sh" /usr/local/sbin/bp-rollback-release
install -m 0755 "${SCRIPT_DIR}/backup-postgres.sh" /usr/local/sbin/bp-backup-postgres
install -m 0755 "${SCRIPT_DIR}/restore-drill.sh" /usr/local/sbin/bp-restore-drill
install -m 0755 "${SCRIPT_DIR}/restore-source-database.sh" /usr/local/sbin/bp-restore-source-database
install -m 0644 "${SCRIPT_DIR}/systemd/bezpieczna-polska-api.service" /etc/systemd/system/bezpieczna-polska-api.service
install -m 0644 "${SCRIPT_DIR}/systemd/bezpieczna-polska-backup.service" /etc/systemd/system/bezpieczna-polska-backup.service
install -m 0644 "${SCRIPT_DIR}/systemd/bezpieczna-polska-backup.timer" /etc/systemd/system/bezpieczna-polska-backup.timer

cat > "/etc/sudoers.d/bezpieczna-polska-deploy" <<EOF
${DEPLOY_USER} ALL=(root) NOPASSWD: /usr/local/sbin/bp-deploy-release
${DEPLOY_USER} ALL=(root) NOPASSWD: /usr/local/sbin/bp-rollback-release
${DEPLOY_USER} ALL=(root) NOPASSWD: /bin/systemctl status bezpieczna-polska-api.service
${DEPLOY_USER} ALL=(root) NOPASSWD: /usr/bin/journalctl -u bezpieczna-polska-api.service
EOF
chmod 0440 /etc/sudoers.d/bezpieczna-polska-deploy
visudo -cf /etc/sudoers.d/bezpieczna-polska-deploy

ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

systemctl daemon-reload
systemctl enable --now bezpieczna-polska-backup.timer

echo "Host bootstrap complete."
echo "Next: configure-database.sh, /etc/bezpieczna-polska/backend.env, DNS and enable-tls.sh."
echo "Deploy user ${DEPLOY_USER} must start a new login session to receive docker group membership."
