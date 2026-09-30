#!/usr/bin/env bash
set -euo pipefail
[[ ${EUID} -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
CONFIG=/etc/bezpieczna-polska/backup-object-storage.json
test -f "$CONFIG"
python3 -m json.tool "$CONFIG" >/dev/null
SOURCE="$(cd "$(dirname "$0")" && pwd)"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y python3-venv
python3 -m venv /opt/bezpieczna-polska/oci-backup-venv
/opt/bezpieczna-polska/oci-backup-venv/bin/pip install 'oci==2.187.0'
install -o root -g root -m 0700 "$SOURCE/upload-backup.py" /usr/local/sbin/bp-upload-backup.py
cat > /usr/local/sbin/bp-backup-upload <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
exec /opt/bezpieczna-polska/oci-backup-venv/bin/python /usr/local/sbin/bp-upload-backup.py "$@"
HOOK
chmod 0700 /usr/local/sbin/bp-backup-upload
chmod 0600 "$CONFIG"
install -o root -g root -m 0700 "$SOURCE/backup-postgres.sh" /usr/local/sbin/bp-backup-postgres
install -o root -g root -m 0644 "$SOURCE/systemd/bezpieczna-polska-backup.service" /etc/systemd/system/
printf 'BP_REQUIRE_OFF_VM_BACKUP=YES\n' > /etc/bezpieczna-polska/backup.env
chmod 0600 /etc/bezpieczna-polska/backup.env
systemctl daemon-reload
echo 'Upload hook installed. Run a fresh backup and remote restore drill before cutover.'
