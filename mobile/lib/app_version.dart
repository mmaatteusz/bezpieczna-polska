// Generated from backend/package.json + mobile/pubspec.yaml by scripts/sync-mobile-version.mjs.
// Run node scripts/sync-mobile-version.mjs after changing both release versions.
const appVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '0.1.0-alpha.53',
);
const appBuildNumber = String.fromEnvironment(
  'APP_BUILD_NUMBER',
  defaultValue: '54',
);
const appChannel = String.fromEnvironment(
  'APP_CHANNEL',
  defaultValue: 'development',
);

String get appVersionLabel {
  if (appChannel == 'preview') {
    return '$appVersion • preview build $appBuildNumber';
  }
  if (appChannel == 'production') {
    return '$appVersion • build $appBuildNumber';
  }
  return '$appVersion • dev build $appBuildNumber';
}
