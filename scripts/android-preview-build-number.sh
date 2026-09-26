#!/usr/bin/env bash
set -euo pipefail

# Preview APKs from different workflows share one package/signing identity.
# Use UTC epoch minutes so every later CI build gets a non-decreasing base
# versionCode regardless of which workflow produced it.
epoch_seconds="${SOURCE_DATE_EPOCH:-$(date -u +%s)}"

if ! [[ "$epoch_seconds" =~ ^[0-9]+$ ]]; then
  echo "SOURCE_DATE_EPOCH must be an integer number of seconds" >&2
  exit 1
fi

build_number=$((epoch_seconds / 60))

# Android's documented maximum versionCode is 2,100,000,000.
# Flutter split-per-ABI arm64 builds add 2000 to the base build number,
# so keep explicit headroom for that transform.
if (( build_number < 1 || build_number > 2099997000 )); then
  echo "Computed preview build number is outside the safe Android range: $build_number" >&2
  exit 1
fi

printf '%s\n' "$build_number"
