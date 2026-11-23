import 'package:bezpieczna_polska/main.dart';
import 'package:bezpieczna_polska/ui/brand_splash.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('loading screen animates the existing logo', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BrandLoadingScreen()));

    expect(find.text('Ładowanie aplikacji…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      'assets/brand/bezpieczna_polska_logo_transparent.png',
    );

    final logoTransform = find.descendant(
      of: find.byType(BrandLoadingScreen),
      matching: find.byType(Transform),
    );
    double scale() =>
        tester.widget<Transform>(logoTransform).transform.entry(0, 0);
    expect(scale(), lessThan(1));
    await tester.pump(const Duration(milliseconds: 600));
    expect(scale(), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bootstrap brings up Start behind the loading cover', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'first_launch_permission_onboarding_completed_v1': true,
    });
    await tester.pumpWidget(const BootstrapApp());
    await tester.pump();
    await tester.pump();

    expect(find.byType(BrandLoadingScreen), findsOneWidget);
    expect(find.byType(Home), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(BrandLoadingScreen), findsNothing);
    expect(find.text('Sytuacja teraz'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a slow server cannot hold the loading cover open', (
    tester,
  ) async {
    await tester.pumpWidget(
      const BrandStartupCover(
        ready: false,
        child: MaterialApp(home: Scaffold(body: Text('Start'))),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(BrandLoadingScreen), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(BrandLoadingScreen), findsNothing);
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('reduced motion skips the transition once data is ready', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: BrandStartupCover(
          ready: true,
          child: MaterialApp(home: Scaffold(body: Text('Start'))),
        ),
      ),
    );
    expect(find.byType(BrandLoadingScreen), findsNothing);
    expect(find.text('Start'), findsOneWidget);
  });
}
