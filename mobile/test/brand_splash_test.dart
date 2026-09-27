import 'package:bezpieczna_polska/ui/brand_splash.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('brand splash covers startup until initial data is ready', (
    tester,
  ) async {
    final ready = ValueNotifier<bool>(false);
    addTearDown(ready.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: BrandSplashGate(
          ready: ready,
          child: const Scaffold(body: Text('Aplikacja gotowa')),
        ),
      ),
    );

    expect(find.text('BEZPIECZNA POLSKA'), findsOneWidget);
    expect(
      find.text('Najważniejsze jest Twoje bezpieczeństwo'),
      findsOneWidget,
    );
    expect(find.text('Ładowanie aplikacji…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Aplikacja gotowa'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1400));
    expect(find.text('BEZPIECZNA POLSKA'), findsOneWidget);

    ready.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
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
