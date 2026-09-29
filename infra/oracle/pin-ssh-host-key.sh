#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-}"
PORT="${2:-22}"
EXPECTED="${EXPECTED_SSH_FINGERPRINT:-}"

if [[ -z "${HOST}" ]]; then
  echo "Usage: EXPECTED_SSH_FINGERPRINT='SHA256:...' $0 <host> [port]" >&2
  exit 1
fi
if [[ ! "${PORT}" =~ ^[0-9]+$ ]] || (( PORT < 1 || PORT > 65535 )); then
  echo "Invalid SSH port." >&2
  exit 1
fi
if [[ ! "${EXPECTED}" =~ ^SHA256:[A-Za-z0-9+/=._-]+$ ]]; then
  echo "EXPECTED_SSH_FINGERPRINT must be a SHA256 fingerprint verified out-of-band." >&2
  exit 1
fi

TMP="$(mktemp)"
trap 'rm -f "${TMP}"' EXIT

ssh-keyscan -p "${PORT}" -T 10 "${HOST}" 2>/dev/null > "${TMP}"
[[ -s "${TMP}" ]] || { echo "No SSH host key received from ${HOST}:${PORT}" >&2; exit 1; }

match=0
while IFS= read -r line; do
  [[ -n "${line}" ]] || continue
  key="$(awk '{print $2" "$3}' <<<"${line}")"
  fingerprint="$(ssh-keygen -lf /dev/stdin -E sha256 <<<"${key}" | awk '{print $2}')"
  algo="$(awk '{print $2}' <<<"${line}")"
  echo "Observed ${algo} ${fingerprint}"
  if [[ "${fingerprint}" == "${EXPECTED}" ]]; then
    match=1
  fi
done < "${TMP}"

if [[ "${match}" -ne 1 ]]; then
  echo "No scanned host key matched EXPECTED_SSH_FINGERPRINT=${EXPECTED}" >&2
  exit 1
fi

echo
echo "Verified known_hosts entry:"
cat "${TMP}"
echo
echo "Copy the verified line(s) above into the ORACLE_SSH_KNOWN_HOSTS GitHub secret."
