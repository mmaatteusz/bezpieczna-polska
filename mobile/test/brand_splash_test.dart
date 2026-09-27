import 'package:bezpieczna_polska/ui/brand_splash.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('brand splash reveals the app without blocking its child', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: BrandSplashGate(child: Scaffold(body: Text('Aplikacja gotowa'))),
      ),
    );

    expect(find.text('BEZPIECZNA POLSKA'), findsOneWidget);
    expect(find.text('Aplikacja gotowa'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();

    expect(find.text('BEZPIECZNA POLSKA'), findsNothing);
    expect(find.text('Aplikacja gotowa'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
