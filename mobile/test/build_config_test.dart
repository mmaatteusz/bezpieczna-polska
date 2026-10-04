import 'package:flutter_test/flutter_test.dart';
import 'package:bezpieczna_polska/build_config.dart';

void main() {
  test(
    'production rejects local and preview endpoints and developer override',
    () {
      for (final url in [
        '',
        'http://api.example.org',
        'https://localhost',
        'https://10.0.2.2',
        'https://api-preview.domain.org',
        'https://api.example',
      ]) {
        expect(
          () => validateBuildConfiguration(
            environment: 'production',
            api: url,
            privacyPolicyUrl: 'https://bezpiecznapolska.pl/privacy',
          ),
          throwsStateError,
        );
      }
      expect(
        () => validateBuildConfiguration(
          environment: 'production',
          api: 'https://api.domain.org',
          developerSettings: true,
          privacyPolicyUrl: 'https://bezpiecznapolska.pl/privacy',
        ),
        throwsStateError,
      );
      expect(
        () => validateBuildConfiguration(
          environment: 'production',
          api: 'https://api.domain.org',
          privacyPolicyUrl: 'https://bezpiecznapolska.pl/privacy',
        ),
        returnsNormally,
      );
    },
  );
  test(
    'production requires a public privacy policy, preview remains usable',
    () {
      for (final url in [
        '',
        'http://bezpiecznapolska.pl/privacy',
        'https://localhost/privacy',
        'https://192.168.0.1/privacy',
        'https://example.com/privacy',
        'https://bezpiecznapolska.pl/privacy.pdf',
        'https://user:password@bezpiecznapolska.pl/privacy',
      ]) {
        expect(
          () => validateBuildConfiguration(
            environment: 'production',
            api: 'https://api.domain.org',
            privacyPolicyUrl: url,
          ),
          throwsStateError,
        );
      }
      expect(
        () => validateBuildConfiguration(environment: 'preview'),
        returnsNormally,
      );
    },
  );
}
