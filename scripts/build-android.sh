#!/usr/bin/env bash
set -euo pipefail
bp_root="$(cd "$(dirname "$0")/.." && pwd)"
node "$bp_root/scripts/check-backend.mjs"
cd "$bp_root/mobile"
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --target-platform android-arm64 \
  --dart-define="API_BASE_URL=$API_BASE_URL" \
  --dart-define=ENABLE_DEVELOPER_SETTINGS=false
