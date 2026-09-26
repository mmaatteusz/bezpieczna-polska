#!/usr/bin/env bash
set -euo pipefail

PACKAGE="pl.bezpiecznapolska.preview"
BASE_APK="${1:-base-preview.apk}"
UPDATE_APK="${2:-update-preview.apk}"

: "${BASE_BUILD:?BASE_BUILD is required}"
: "${NEXT_BUILD:?NEXT_BUILD is required}"

echo "Installing base APK versionCode=$BASE_BUILD"
adb install "$BASE_APK"
adb shell dumpsys package "$PACKAGE" | grep -F "versionCode=$BASE_BUILD"

adb shell run-as "$PACKAGE" sh -c 'mkdir -p files && printf keep-me > files/update-sentinel'
SENTINEL="$(adb shell run-as "$PACKAGE" cat files/update-sentinel | tr -d '\r')"
test "$SENTINEL" = "keep-me"

echo "Updating in place to versionCode=$NEXT_BUILD"
adb install -r "$UPDATE_APK"
adb shell dumpsys package "$PACKAGE" | grep -F "versionCode=$NEXT_BUILD"

SENTINEL="$(adb shell run-as "$PACKAGE" cat files/update-sentinel | tr -d '\r')"
test "$SENTINEL" = "keep-me"

echo "Confirming Android rejects downgrade without -d"
set +e
DOWNGRADE_OUTPUT="$(adb install -r "$BASE_APK" 2>&1)"
DOWNGRADE_STATUS=$?
set -e
printf '%s\n' "$DOWNGRADE_OUTPUT"

if [[ $DOWNGRADE_STATUS -eq 0 ]]; then
  echo "Unexpected downgrade/reinstall to the lower versionCode was accepted" >&2
  exit 1
fi

if ! grep -Eiq 'version downgrade|INSTALL_FAILED_VERSION_DOWNGRADE' <<<"$DOWNGRADE_OUTPUT"; then
  echo "Downgrade failed, but not for the expected versionCode reason" >&2
  exit 1
fi

echo "Android PackageManager accepted the signed in-place update, preserved app data, and rejected downgrade."
