import 'dart:io';
import 'dart:ui' as ui;

import 'package:bezpieczna_polska/screens/dashboard_screen.dart';
import 'package:bezpieczna_polska/ui/app_chrome.dart';
import 'package:bezpieczna_polska/ui/app_theme.dart';
import 'package:bezpieczna_polska/ui/province_outline.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dashboard_situation_test.dart' show snapshot, around;
import 'start_alert_regression_test.dart' show warning;

void main() {
  setUpAll(() async {
    for (final font in {
      'Roboto': 'test/fonts/Roboto-Regular.ttf',
      'MaterialIcons': 'test/fonts/MaterialIcons-Regular.otf',
      'Source Serif 4': 'assets/fonts/SourceSerif4-Semibold.ttf',
    }.entries) {
      final loader = FontLoader(font.key);
      loader.addFont(
        Future.value(ByteData.sublistView(File(font.value).readAsBytesSync())),
      );
      await loader.load();
    }
  });

  testWidgets('critical country warning stays visible and Start actions work', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final country = snapshot(now);
    var mapOpens = 0;
    var localityChanges = 0;
    var eventOpens = 0;
    final boundaryKey = GlobalKey();
    final alerts = [
      warning(
        id: 'rain',
        title: 'Intensywne opady deszczu',
        description: 'Zachowaj ostrożność.',
        validTo: now.add(const Duration(hours: 7)).toUtc().toIso8601String(),
        sourceId: 'IMGW_METEO',
        sourceName: 'IMGW',
      ),
    ];
    Future<void> show([Brightness brightness = Brightness.dark]) =>
        tester.pumpWidget(
          MaterialApp(
            theme: buildSafetyTheme(brightness),
            home: RepaintBoundary(
              key: boundaryKey,
              child: Scaffold(
                appBar: SafetyAppBar(page: 0, onSettings: () {}),
                body: DashboardScreen(
                  snapshot: country,
                  events: alerts,
                  localityAround: around(now, events: alerts),
                  offlinePackage: null,
                  online: true,
                  loading: false,
                  backgroundSync: false,
                  region: '04',
                  localityLabel: 'Bydgoszcz',
                  error: null,
                  onRefresh: () async {},
                  onChooseLocality: () => localityChanges++,
                  onOpenMap: () => mapOpens++,
                  onOpenAlerts: () {},
                  onOpenSecurityLevels: () {},
                  onOpenEvent: (_) => eventOpens++,
                ),
                bottomNavigationBar: SafetyTabBar(
                  selectedIndex: 0,
                  onDestinationSelected: (_) {},
                ),
              ),
            ),
          ),
        );
    await show();
    await tester.pumpAndSettle();
    expect(find.text('Polska'), findsNothing);
    await tester.tap(find.text('Otwórz mapę'));
    await tester.tap(find.text('Zmień miejscowość'));
    expect(mapOpens, 1);
    expect(localityChanges, 1);
    expect(tester.takeException(), isNull);
    expect(find.text('POTWIERDZONE'), findsNothing);
    await tester.pumpAndSettle();
    if (const bool.fromEnvironment('CAPTURE_START')) {
      final outline = find.descendant(
        of: find.byType(ProvinceOutline),
        matching: find.byType(CustomPaint),
      );
      for (
        var attempt = 0;
        tester.widget<CustomPaint>(outline).painter == null && attempt < 20;
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();
      }
      expect(tester.widget<CustomPaint>(outline).painter, isNotNull);
      for (final brightness in Brightness.values) {
        await show(brightness);
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final rendered = await boundary.toImage(pixelRatio: 2);
          final png = await rendered.toByteData(format: ui.ImageByteFormat.png);
          final file = File('../output/start-beta-${brightness.name}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(png!.buffer.asUint8List());
          rendered.dispose();
        });
      }
    }
    await tester.tap(find.text('Intensywne opady deszczu'));
    expect(eventOpens, 1);
    country.data['nationalStatus']['hazardLevel'] = 'ACTIVE_DANGER';
    country.data['nationalStatus']['displayText'] =
        'Krytyczne zagrożenie krajowe';
    await show();
    await tester.pumpAndSettle();
    expect(find.text('Polska'), findsOneWidget);
    expect(find.text('POWAŻNE ZAGROŻENIE'), findsOneWidget);
    expect(find.text('Krytyczne zagrożenie krajowe'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
