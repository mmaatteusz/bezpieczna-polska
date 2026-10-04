// A second gate at application startup complements the release workflow's build check.
const appEnvironment = String.fromEnvironment(
  'APP_ENV',
  defaultValue: 'development',
);
const compiledApi = String.fromEnvironment('API_BASE_URL');
const compiledPrivacyPolicyUrl = String.fromEnvironment('PRIVACY_POLICY_URL');

bool isPublicPrivacyPolicyUrl(String value) {
  final uri = Uri.tryParse(value);
  final host = uri?.host.toLowerCase() ?? '';
  return uri != null &&
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      host.contains('.') &&
      !host.contains(':') &&
      !RegExp(r'^[0-9.]+$').hasMatch(host) &&
      !RegExp(
        r'(^|\.)(localhost|local|test|example|invalid|example\.(com|org|net))$',
      ).hasMatch(host) &&
      !uri.path.toLowerCase().endsWith('.pdf');
}

const compiledDeveloperSettings = bool.fromEnvironment(
  'ENABLE_DEVELOPER_SETTINGS',
);

void validateBuildConfiguration({
  String environment = appEnvironment,
  String api = compiledApi,
  bool developerSettings = compiledDeveloperSettings,
  String privacyPolicyUrl = compiledPrivacyPolicyUrl,
}) {
  if (!{'development', 'preview', 'production'}.contains(environment)) {
    throw StateError('Invalid APP_ENV');
  }
  if (environment != 'production') return;
  if (!isPublicPrivacyPolicyUrl(privacyPolicyUrl)) {
    throw StateError('Production requires a public HTTPS privacy policy URL');
  }
  final uri = Uri.tryParse(api);
  final host = uri?.host.toLowerCase() ?? '';
  if (developerSettings ||
      uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.path.isNotEmpty && uri.path != '/' ||
      host.isEmpty ||
      !host.contains('.') ||
      host == 'localhost' ||
      host.endsWith('.localhost') ||
      RegExp(r'(^|\.)(local|test|example|invalid|example\.(com|org|net))$')
          .hasMatch(host) ||
      RegExp(r'(^|[.-])(dev|development|staging|preview)([.-]|$)')
          .hasMatch(host) ||
      RegExp(
        r'^(127\.|10\.|192\.168\.|169\.254\.|0\.|172\.(1[6-9]|2\d|3[01])\.)',
      ).hasMatch(host) ||
      host.contains(':')) {
    throw StateError(
      'Production requires a real HTTPS API and disabled developer settings',
    );
  }
}
