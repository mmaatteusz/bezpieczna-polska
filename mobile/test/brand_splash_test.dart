import 'package:bezpieczna_polska/ui/brand_splash.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('loading screen shows approved logo, safety copy and progress', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: BrandLoadingScreen()));

    expect(
      find.text('Najważniejsze jest Twoje bezpieczeństwo'),
      findsOneWidget,
    );
    expect(find.text('Ładowanie aplikacji…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);

    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      'assets/brand/bezpieczna_polska_logo_transparent.png',
    );
    expect(tester.takeException(), isNull);
  });
}
