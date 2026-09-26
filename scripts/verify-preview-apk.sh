#!/usr/bin/env bash
set -euo pipefail

EXPECTED_PREVIEW_CERT_SHA256="1f7f3f2aea7073889563b7461e7dfd8f80929a36fff8138c51a2a9516db153d2"
EXPECTED_PACKAGE="pl.bezpiecznapolska.preview"

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <apk> <base-build-number> [split-arm64|plain]" >&2
  exit 2
fi

apk="$1"
base_build="$2"
mode="${3:-split-arm64}"

if [[ ! -f "$apk" ]]; then
  echo "APK not found: $apk" >&2
  exit 1
fi
if ! [[ "$base_build" =~ ^[0-9]+$ ]]; then
  echo "Build number must be numeric: $base_build" >&2
  exit 1
fi

apksigner="${ANDROID_HOME:-}/build-tools/36.0.0/apksigner"
aapt="${ANDROID_HOME:-}/build-tools/36.0.0/aapt"
if [[ ! -x "$apksigner" || ! -x "$aapt" ]]; then
  echo "Android build-tools 36.0.0 are required" >&2
  exit 1
fi

case "$mode" in
  split-arm64) expected_code=$((base_build + 2000)) ;;
  plain) expected_code="$base_build" ;;
  *) echo "Unknown mode: $mode" >&2; exit 2 ;;
esac

tmp="${RUNNER_TEMP:-/tmp}/bp-apk-check-$$"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT

"$apksigner" verify --verbose --print-certs "$apk" | tee "$tmp/signature.txt"
"$aapt" dump badging "$apk" | tee "$tmp/package.txt"

grep -F "Signer #1 certificate SHA-256 digest: $EXPECTED_PREVIEW_CERT_SHA256" "$tmp/signature.txt"
grep -F "Verified using v2 scheme (APK Signature Scheme v2): true" "$tmp/signature.txt"
grep -F "name='$EXPECTED_PACKAGE'" "$tmp/package.txt"
grep -F "versionCode='$expected_code'" "$tmp/package.txt"

if [[ "$mode" == "split-arm64" ]]; then
  grep -F "native-code: 'arm64-v8a'" "$tmp/package.txt"
  if grep -E "native-code:.*(armeabi-v7a|x86_64)" "$tmp/package.txt"; then
    echo "Unexpected non-arm64 native libraries in arm64 preview APK" >&2
    exit 1
  fi
fi

echo "Preview APK contract verified: package=$EXPECTED_PACKAGE versionCode=$expected_code signer=$EXPECTED_PREVIEW_CERT_SHA256"
