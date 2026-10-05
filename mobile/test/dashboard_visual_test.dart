import 'dart:io';
import 'dart:ui' as ui;

import 'package:bezpieczna_polska/screens/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dashboard_situation_test.dart' show snapshot, around;
import 'start_alert_regression_test.dart' show warning;

void main() {
  setUpAll(() async {
    for (final font in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      final loader = FontLoader(font.key);
      loader.addFont(
        Future.value(
          ByteData.sublistView(
            File('test/fonts/${font.value}').readAsBytesSync(),
          ),
        ),
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
        validTo: '2099-01-01T00:00:00Z',
      ),
    ];
    Future<void> show() => tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorSchemeSeed: Colors.teal,
          brightness: Brightness.dark,
        ),
        home: RepaintBoundary(
          key: boundaryKey,
          child: Scaffold(
            appBar: AppBar(title: const Text('Bezpieczna Polska')),
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
            bottomNavigationBar: NavigationBar(
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  label: 'Start',
                ),
                NavigationDestination(
                  icon: Icon(Icons.map_outlined),
                  label: 'Mapa',
                ),
                NavigationDestination(
                  icon: Icon(Icons.notifications_outlined),
                  label: 'Alerty',
                ),
                NavigationDestination(
                  icon: Icon(Icons.more_horiz),
                  label: 'Więcej',
                ),
              ],
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
      await tester.runAsync(() async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final rendered = await boundary.toImage(pixelRatio: 2);
        final png = await rendered.toByteData(format: ui.ImageByteFormat.png);
        final file = File('../output/start-beta-dark.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(png!.buffer.asUint8List());
        rendered.dispose();
      });
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
