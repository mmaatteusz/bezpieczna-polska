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
          () => validateBuildConfiguration(environment: 'production', api: url),
          throwsStateError,
        );
      }
      expect(
        () => validateBuildConfiguration(
          environment: 'production',
          api: 'https://api.domain.org',
          developerSettings: true,
        ),
        throwsStateError,
      );
      expect(
        () => validateBuildConfiguration(
          environment: 'production',
          api: 'https://api.domain.org',
        ),
        returnsNormally,
      );
    },
  );
}
