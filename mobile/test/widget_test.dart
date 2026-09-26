import 'dart:io';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bezpieczna_polska/main.dart';
import 'package:bezpieczna_polska/model.dart';

// Only the native surface is substituted. Data parsing/cache have independent tests.
class TestMapPlatform extends MapLibrePlatform {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Widget buildView(
    Map<String, dynamic> creationParams,
    OnPlatformViewCreatedCallback onPlatformViewCreated,
    Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers,
  ) => const SizedBox(key: ValueKey('native-map-surface'));
}

void main() {
  test(
    'national scope does not silently seed Kujawsko for locality selection',
    () {
      expect(localityRegionSeed('PL'), isNull);
      expect(localityRegionSeed('14'), '14');
    },
  );
  setUp(() {
    final original = MapLibrePlatform.createInstance;
    MapLibrePlatform.createInstance = () => TestMapPlatform();
    addTearDown(() => MapLibrePlatform.createInstance = original);
  });
  setUpAll(() async {
    for (final f in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      final loader = FontLoader(f.key);
      loader.addFont(
        Future.value(
          ByteData.sublistView(File('test/fonts/${f.value}').readAsBytesSync()),
        ),
      );
      await loader.load();
    }
  });
  testWidgets('four-tab phone layout, focused home, map and deliberate SOS', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final r = DataRepository(await SharedPreferences.getInstance());
    await tester.pumpWidget(SafetyApp(repository: r));
    await tester.pumpAndSettle();

    expect(find.text('Sytuacja teraz'), findsOneWidget);
    expect(find.text('Polska'), findsOneWidget);
    expect(find.text('Twoja okolica'), findsOneWidget);
    expect(find.text('Ustaw lokalizację'), findsOneWidget);
    expect(find.text('Bezpieczna Polska'), findsOneWidget);
    expect(find.text('Istotne zagrożenia'), findsOneWidget);
    expect(find.text('Źródła i aktualność'), findsNothing);
    expect(find.text('Diagnostyka źródeł'), findsNothing);
    expect(find.byType(NavigationDestination), findsNWidgets(4));

    await tester.tap(find.text('Ustaw lokalizację'));
    await tester.pumpAndSettle();
    expect(find.text('Wybierz swoją okolicę'), findsOneWidget);
    await tester.tap(find.text('Anuluj'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Polska'));
    await tester.pumpAndSettle();
    expect(find.text('Alerty'), findsWidgets);
    await tester.tap(find.text('Start').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mapa').last);
    await tester.pumpAndSettle();
    expect(find.byType(MapLibreMap), findsOneWidget);
    expect(find.byKey(const ValueKey('native-map-surface')), findsOneWidget);
    expect(find.byTooltip('Warstwy mapy'), findsOneWidget);
    expect(find.byTooltip('Wróć do wybranej miejscowości'), findsOneWidget);

    await tester.tap(find.text('Więcej').last);
    await tester.pumpAndSettle();
    expect(find.text('Schronienia'), findsOneWidget);
    expect(find.text('NEPTUN'), findsOneWidget);
    expect(find.text('Obserwowane miejsca'), findsOneWidget);
    expect(
      find.byType(MapLibreMap, skipOffstage: false),
      findsOneWidget,
      reason: 'Visited tabs must stay mounted instead of being torn down.',
    );

    for (final label in ['Start', 'Alerty', 'Mapa', 'Więcej']) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    await tester.tap(find.text('Schronienia'));
    await tester.pumpAndSettle();
    expect(
      find.text('Brak zweryfikowanego pakietu schronienia'),
      findsOneWidget,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('112 • Numer alarmowy'));
    await tester.pumpAndSettle();
    expect(find.text('Otworzyć telefon z numerem 112?'), findsOneWidget);
    await tester.tap(find.text('Anuluj'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'configured locality card scrolls to warnings instead of reopening picker',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'region': '04',
        'primary_location_label': 'Bydgoszcz',
        'primary_location_latitude': 53.1235,
        'primary_location_longitude': 18.0084,
      });
      final r = DataRepository(await SharedPreferences.getInstance());
      await tester.pumpWidget(SafetyApp(repository: r));
      await tester.pumpAndSettle();

      expect(find.text('Ustaw lokalizację'), findsNothing);
      final warnings = find.text('Istotne zagrożenia');
      final before = tester.getTopLeft(warnings).dy;

      await tester.tap(find.text('Twoja okolica'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Wybierz swoją okolicę'), findsNothing);
      expect(tester.getTopLeft(warnings).dy, lessThan(before));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('200 percent font on phone does not overflow status', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final r = DataRepository(await SharedPreferences.getInstance());
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Home(repository: r, onTheme: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'normal settings hide server input; Developer Settings contain the override',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final r = DataRepository(
        await SharedPreferences.getInstance(),
        developerSettingsEnabled: true,
      );
      await tester.pumpWidget(SafetyApp(repository: r));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Ustawienia'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Diagnostyka źródeł'), findsOneWidget);
      await tester.tap(find.text('Developer Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Backend URL (HTTPS)'), findsOneWidget);
      await tester.tap(find.text('Anuluj'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'fresh installation connects automatically using build configuration',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      var requests = 0;
      final now = DateTime.now().toUtc();
      final status = {
        'displayText': 'Brak wystarczających aktualnych danych',
        'hazardLevel': 'UNKNOWN',
        'validUntil': now.add(const Duration(minutes: 1)).toIso8601String(),
      };
      final r = DataRepository(
        await SharedPreferences.getInstance(),
        buildApi: 'https://build.example',
        developerSettingsEnabled: false,
        client: MockClient((request) async {
          requests++;
          expect(request.url.host, 'build.example');
          return http.Response(
            jsonEncode({
              'schemaVersion': 1,
              'regionId': request.url.queryParameters['regionId'] ?? 'PL',
              'serverTime': now.toIso8601String(),
              'status': status,
              'nationalStatus': status,
              'events': [],
              'sources': [],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      await tester.pumpWidget(SafetyApp(repository: r));
      await tester.pumpAndSettle();
      expect(requests, greaterThanOrEqualTo(2));
      expect(
        find.text('Brak wystarczających aktualnych danych'),
        findsOneWidget,
      );
      expect(find.text('Ustaw lokalizację'), findsOneWidget);
      await tester.tap(find.byTooltip('Ustawienia'));
      await tester.pumpAndSettle();
      expect(find.text('Developer Settings'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
