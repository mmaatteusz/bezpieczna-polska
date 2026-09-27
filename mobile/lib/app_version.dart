// Generated from backend/package.json + mobile/pubspec.yaml by scripts/sync-mobile-version.mjs.
// Run node scripts/sync-mobile-version.mjs after changing both release versions.
const appVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '0.1.0-alpha.23',
);
const appBuildNumber = String.fromEnvironment(
  'APP_BUILD_NUMBER',
  defaultValue: '24',
);
const appChannel = String.fromEnvironment(
  'APP_CHANNEL',
  defaultValue: 'development',
);

String get appVersionLabel {
  final prefix = appChannel == 'preview'
      ? 'preview build'
      : appChannel == 'production'
      ? 'build'
      : 'dev build';
  return '$appVersion • $prefix $appBuildNumber';
}
