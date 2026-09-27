import 'package:bezpieczna_polska/ui/brand_splash.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('loading screen keeps the safety message and progress visible', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: BrandLoadingScreen()));

    expect(
      find.text('Najważniejsze jest Twoje bezpieczeństwo'),
      findsOneWidget,
    );
    expect(find.text('BEZPIECZNA POLSKA'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
