import 'package:bezpieczna_polska/map_interaction.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('embedded maps eagerly claim gestures from surrounding scroll views', () {
    final recognizers = mapGestureRecognizers();

    expect(recognizers, hasLength(1));
    expect(recognizers.single.type, EagerGestureRecognizer);

    final recognizer = recognizers.single.constructor();
    expect(recognizer, isA<EagerGestureRecognizer>());
    recognizer.dispose();
  });
}
