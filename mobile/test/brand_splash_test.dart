import 'package:bezpieczna_polska/ui/brand_splash.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('brand splash shows one loading screen before the app', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: BrandSplashGate(child: Scaffold(body: Text('Aplikacja gotowa'))),
      ),
    );

    expect(find.text('BEZPIECZNA POLSKA'), findsOneWidget);
    expect(
      find.text('Najważniejsze jest Twoje bezpieczeństwo'),
      findsOneWidget,
    );
    expect(find.text('Ładowanie aplikacji…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Aplikacja gotowa'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1700));
    await tester.pumpAndSettle();

    expect(find.text('BEZPIECZNA POLSKA'), findsNothing);
    expect(
      find.text('Najważniejsze jest Twoje bezpieczeństwo'),
      findsNothing,
    );
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Aplikacja gotowa'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
