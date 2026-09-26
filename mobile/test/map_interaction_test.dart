import 'package:bezpieczna_polska/map_interaction.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'embedded maps eagerly claim gestures from surrounding scroll views',
    () {
      final recognizers = mapGestureRecognizers();

      expect(recognizers, hasLength(1));
      expect(recognizers.single.type, EagerGestureRecognizer);

      final recognizer = recognizers.single.constructor();
      expect(recognizer, isA<EagerGestureRecognizer>());
      recognizer.dispose();
    },
  );

  test(
    'shelter navigation uses exact coordinates and current device origin',
    () {
      final url = shelterNavigationUrl(
        latitude: 53.123456,
        longitude: 18.012345,
      );
      final uri = Uri.parse(url);

      expect(uri.scheme, 'https');
      expect(uri.host, 'www.google.com');
      expect(uri.path, '/maps/dir/');
      expect(uri.queryParameters['api'], '1');
      expect(uri.queryParameters['destination'], '53.123456,18.012345');
      expect(uri.queryParameters['travelmode'], 'driving');
      expect(uri.queryParameters['dir_action'], 'navigate');
      expect(uri.queryParameters.containsKey('origin'), isFalse);
    },
  );

  test('shelter navigation rejects invalid coordinates', () {
    expect(
      () => shelterNavigationUrl(latitude: 91, longitude: 18),
      throwsArgumentError,
    );
    expect(
      () => shelterNavigationUrl(latitude: 53, longitude: double.nan),
      throwsArgumentError,
    );
  });
}
