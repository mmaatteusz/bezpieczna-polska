#!/usr/bin/env bash
set -euo pipefail

EXPECTED_PREVIEW_CERT_SHA256="1f7f3f2aea7073889563b7461e7dfd8f80929a36fff8138c51a2a9516db153d2"
KEYSTORE_PATH="${1:-${RUNNER_TEMP:-/tmp}/preview-signing.jks}"

for key in ANDROID_PREVIEW_KEYSTORE_B64 ANDROID_PREVIEW_KEYSTORE_PASSWORD ANDROID_PREVIEW_KEY_ALIAS ANDROID_PREVIEW_KEY_PASSWORD; do
  if [[ -z "${!key:-}" ]]; then
    echo "Missing required preview signing variable: $key" >&2
    exit 1
  fi
done

echo "$ANDROID_PREVIEW_KEYSTORE_B64" | base64 --decode > "$KEYSTORE_PATH"
chmod 600 "$KEYSTORE_PATH"

keytool -list   -keystore "$KEYSTORE_PATH"   -storepass "$ANDROID_PREVIEW_KEYSTORE_PASSWORD"   -alias "$ANDROID_PREVIEW_KEY_ALIAS" >/dev/null

ACTUAL_CERT_SHA256="$(
  keytool -exportcert     -keystore "$KEYSTORE_PATH"     -storepass "$ANDROID_PREVIEW_KEYSTORE_PASSWORD"     -alias "$ANDROID_PREVIEW_KEY_ALIAS" |
    sha256sum |
    awk '{print $1}'
)"

if [[ "$ACTUAL_CERT_SHA256" != "$EXPECTED_PREVIEW_CERT_SHA256" ]]; then
  echo "Preview signing certificate mismatch." >&2
  echo "Expected: $EXPECTED_PREVIEW_CERT_SHA256" >&2
  echo "Actual:   $ACTUAL_CERT_SHA256" >&2
  echo "Refusing to build an APK that would break in-place updates." >&2
  exit 1
fi

if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "ANDROID_PREVIEW_KEYSTORE_PATH=$KEYSTORE_PATH" >> "$GITHUB_ENV"
else
  export ANDROID_PREVIEW_KEYSTORE_PATH="$KEYSTORE_PATH"
fi

echo "Stable preview signer verified: $ACTUAL_CERT_SHA256"
