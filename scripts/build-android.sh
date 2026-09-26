#!/usr/bin/env bash
set -euo pipefail

bp_root="$(cd "$(dirname "$0")/.." && pwd)"
node "$bp_root/scripts/check-backend.mjs"

# Local builds are deliberately development builds. The distributable preview
# package is reserved for CI, where the permanent preview signer is available.
export BP_ENV="${BP_ENV:-development}"
if [[ "$BP_ENV" == "preview" ]]; then
  echo "Refusing an implicit local preview build. Use the CI preview artifact or configure the permanent preview signer explicitly." >&2
  exit 1
fi

cd "$bp_root/mobile"
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --target-platform android-arm64 \
  --dart-define="APP_ENV=$BP_ENV" \
  --dart-define="API_BASE_URL=$API_BASE_URL" \
  --dart-define=ENABLE_DEVELOPER_SETTINGS=false
