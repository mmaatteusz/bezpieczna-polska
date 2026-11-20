import 'dart:io';
import 'dart:ui' as ui;

import 'package:bezpieczna_polska/screens/dashboard_screen.dart';
import 'package:bezpieczna_polska/ui/app_chrome.dart';
import 'package:bezpieczna_polska/ui/app_theme.dart';
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
    var localityChanges = 0;
    var eventOpens = 0;
    var refreshes = 0;
    final boundaryKey = GlobalKey();
    final alerts = [
      warning(
          id: 'rain',
          title: 'Intensywne opady deszczu',
          description: 'Zachowaj ostrożność.',
          validTo: now.add(const Duration(hours: 4)).toUtc().toIso8601String(),
          sourceId: 'IMGW_METEO',
          sourceName: 'IMGW',
        )
        ..data.addAll({
          'locationText': 'Bydgoszcz i powiat bydgoski',
          'instructions': ['Śledź aktualizacje komunikatu IMGW.'],
        }),
      warning(
          id: 'wind',
          title: 'Silne porywy wiatru',
          validTo: now.add(const Duration(hours: 6)).toUtc().toIso8601String(),
          sourceId: 'IMGW_METEO',
          sourceName: 'IMGW',
        )
        ..data.addAll({
          'locationText': 'Powiat bydgoski',
          'severity': 'ELEVATED',
        }),
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
                  onRefresh: () async => refreshes++,
                  onChooseLocality: () => localityChanges++,
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
    expect(
      tester.getTopLeft(find.text('Intensywne opady deszczu')).dy,
      lessThan(270),
    );
    await tester.tap(find.byTooltip('Odśwież dane'));
    await tester.tap(find.text('Bydgoszcz'));
    expect(refreshes, 1);
    expect(localityChanges, 1);
    expect(tester.takeException(), isNull);
    expect(find.text('POTWIERDZONE'), findsNothing);
    await tester.pumpAndSettle();
    if (const bool.fromEnvironment('CAPTURE_START')) {
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
