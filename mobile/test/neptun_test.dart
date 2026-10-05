import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:bezpieczna_polska/model.dart';
import 'package:bezpieczna_polska/neptun.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> fixture(DateTime now) {
  final ended = now.subtract(const Duration(hours: 48));
  final started = ended.subtract(const Duration(hours: 2));
  return {
    'schemaVersion': 2,
    'mode': 'LIVE_AND_HISTORY',
    'serverTime': now.toIso8601String(),
    'safetyDelayHours': 24,
    'minimumPublishedPrecisionKm': 10,
    'coverage': 'CURATED_HISTORY',
    'sourceHealth': null,
    'live': {
      'state': 'LIVE',
      'sourceUrl': 'https://neptun.in.ua/',
      'sourceName': 'NEPTUN',
      'lastSuccessfulSyncAt': now.toIso8601String(),
      'sourceServerTime': now.toIso8601String(),
      'validUntil': now.add(const Duration(minutes: 2)).toIso8601String(),
      'attribution': 'Dane live: NEPTUN — neptun.in.ua',
      'disclaimer': 'coarse live only',
      'threats': [
        {
          'id': 'trk-live-1',
          'type': 'fpv',
          'title': 'FPV / dron',
          'region': 'Obwód testowy',
          'confidenceLevel': 'high',
          'sourceCount': 3,
          'count': 1,
          'updatedAt': now.toIso8601String(),
          'status': 'active',
          'advisory': false,
          'areaOnly': false,
          'latitude': 49.1,
          'longitude': 31.2,
          'precisionKm': 10,
          'sourceUrl': 'https://neptun.in.ua/',
        },
      ],
      'map': {
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'id': 'NEPTUN-LIVE-trk-live-1',
            'geometry': {
              'type': 'Point',
              'coordinates': [31.2, 49.1],
            },
            'properties': {
              'threatId': 'trk-live-1',
              'type': 'fpv',
              'live': true,
              'coarse': true,
            },
          },
        ],
      },
    },
    'disclaimer': 'history only',
    'tracks': [
      {
        'id': 'NEPTUN-fixture',
        'title': 'Historyczny ślad testowy',
        'description': 'Syntetyczny fixture.',
        'objectType': 'AIR_OBJECT',
        'lifecycle': 'ENDED',
        'verification': 'PROBABLE',
        'startedAt': started.toIso8601String(),
        'endedAt': ended.toIso8601String(),
        'directionText': 'zachód → wschód',
        'revision': 1,
        'reviewed': true,
        'observations': [
          {
            'id': 'obs-1',
            'observedAt': started
                .add(const Duration(minutes: 15))
                .toIso8601String(),
            'latitude': 52.1,
            'longitude': 21.0,
            'precisionKm': 20,
            'locationText': 'obszar A',
            'verification': 'PROBABLE',
            'source': {
              'id': 'OSINT-A',
              'name': 'Źródło testowe A',
              'url': 'https://example.com/a',
              'tier': 3,
              'origin': 'OSINT',
            },
            'note': null,
            'correction': null,
          },
          {
            'id': 'obs-2',
            'observedAt': ended
                .subtract(const Duration(minutes: 10))
                .toIso8601String(),
            'latitude': 52.5,
            'longitude': 21.4,
            'precisionKm': 25,
            'locationText': 'obszar B',
            'verification': 'PROBABLE',
            'source': {
              'id': 'OSINT-B',
              'name': 'Źródło testowe B',
              'url': 'https://example.com/b',
              'tier': 3,
              'origin': 'OSINT',
            },
            'note': null,
            'correction': null,
          },
        ],
      },
    ],
    'map': {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'id': 'NEPTUN-fixture',
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              [21.0, 52.1],
              [21.4, 52.5],
            ],
          },
          'properties': {
            'trackId': 'NEPTUN-fixture',
            'title': 'Historyczny ślad testowy',
            'objectType': 'AIR_OBJECT',
            'verification': 'PROBABLE',
            'endedAt': ended.toIso8601String(),
            'directionText': 'zachód → wschód',
            'observationCount': 2,
            'historicalOnly': true,
          },
        },
      ],
    },
  };
}

http.Response jsonResponse(Object value, int status) => http.Response.bytes(
  utf8.encode(jsonEncode(value)),
  status,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('NEPTUN symbols retain readable pixels at phone densities', () async {
    for (final type in [
      'uav',
      'fpv',
      'recon',
      'missile',
      'ballistic',
      'kab',
      'mig31k',
      'unknown',
    ]) {
      for (final ratio in [1.0, 2.0, 3.0, 3.5]) {
        final codec = await ui.instantiateImageCodec(
          await neptunIconPng(type, pixelRatio: ratio),
        );
        final frame = await codec.getNextFrame();
        expect(frame.image.width, (40 * ratio).ceil());
        expect(frame.image.height, (40 * ratio).ceil());
        final pixels = (await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        var white = 0;
        for (var i = 0; i < pixels.lengthInBytes; i += 4) {
          if (pixels.getUint8(i) > 230 &&
              pixels.getUint8(i + 1) > 230 &&
              pixels.getUint8(i + 2) > 230 &&
              pixels.getUint8(i + 3) > 230) {
            white++;
          }
        }
        expect(white, greaterThan(20 * ratio * ratio), reason: type);
        frame.image.dispose();
        codec.dispose();
      }
    }
  });
  test(
    'status entry point wording advertises live data without precise-motion claims',
    () {
      final source = File('lib/screens/more_screen.dart').readAsStringSync();
      expect(source, contains("title: 'NEPTUN'"));
      expect(source, contains('Bieżące zgrubne zagrożenia i historia'));
      expect(source, isNot(contains('kursu')));
      expect(source, isNot(contains('prędkości')));
      expect(source, isNot(contains('predykcji ruchu')));
    },
  );
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 9, 22, 12);

  test(
    'NEPTUN parser accepts live coarse threats and historical coarse tracks',
    () {
      final data = NeptunData.parse(fixture(now));
      expect(data.liveThreats.length, 1);
      expect(data.liveThreats.first['precisionKm'], 10);
      expect(data.liveThreats.first['type'], 'fpv');
      expect(data.isFreshLive(now), isTrue);
      expect(data.tracks.length, 1);
      expect(data.tracks.first['lifecycle'], 'ENDED');

      final stale = fixture(now);
      stale['live']['validUntil'] = now
          .subtract(const Duration(seconds: 1))
          .toIso8601String();
      expect(NeptunData.parse(stale).isFreshLive(now), isFalse);

      final operationalLeak = fixture(now);
      operationalLeak['live']['threats'][0]['presumptiveCourse'] = true;
      expect(() => NeptunData.parse(operationalLeak), throwsFormatException);

      final iconMismatch = fixture(now);
      iconMismatch['live']['map']['features'][0]['properties']['type'] = 'uav';
      expect(() => NeptunData.parse(iconMismatch), throwsFormatException);

      final active = fixture(now);
      active['tracks'][0]['lifecycle'] = 'ACTIVE';
      expect(() => NeptunData.parse(active), throwsFormatException);

      final exact = fixture(now);
      exact['tracks'][0]['observations'][0]['precisionKm'] = 1;
      expect(() => NeptunData.parse(exact), throwsFormatException);

      final recent = fixture(now);
      recent['tracks'][0]['endedAt'] = now
          .subtract(const Duration(hours: 2))
          .toIso8601String();
      expect(() => NeptunData.parse(recent), throwsFormatException);
    },
  );

  test('NEPTUN map forwards feature taps to the map tap handler', () {
    final source = File('lib/neptun.dart').readAsStringSync();
    expect(source, contains('featureTapsTriggersMapClick: true'));
  });

  test(
    'NEPTUN live map uses typed threat symbols instead of visible red dots',
    () {
      final source = File('lib/neptun.dart').readAsStringSync();
      expect(source, contains("'neptun-live-symbols'"));
      expect(source, contains("'neptun-icon-fpv'"));
      expect(source, contains("'neptun-icon-missile'"));
      expect(source, contains('const ui.Color(0xffffffff)'));
      expect(source, isNot(contains('0xff7f1d1d')));
      expect(source, isNot(contains("circleColor: '#c62828'")));
    },
  );

  test('NEPTUN map tap resolves the live threat behind a threat symbol', () {
    final data = NeptunData.parse(fixture(now));
    final feature = (data.live['map']['features'] as List).first;
    final threat = neptunThreatForFeature(data, feature);

    expect(threat, isNotNull);
    expect(threat!['id'], 'trk-live-1');
    expect(threat['title'], 'FPV / dron');
    expect(neptunTypeLabel(threat['type'] as String), 'FPV / dron');
    expect(neptunMapIconId('fpv'), 'neptun-icon-fpv');
    expect(neptunMapIconId('missile'), 'neptun-icon-missile');
    expect(neptunMapIconId('unknown'), 'neptun-icon-unknown');
    expect(neptunMapIconId('future-type'), 'neptun-icon-unknown');
    expect(
      neptunThreatForFeature(data, {
        'properties': {'threatId': 'missing'},
      }),
      isNull,
    );
    expect(neptunThreatForFeature(data, const <String, dynamic>{}), isNull);
  });

  test(
    'NEPTUN persistence is throttled independently from five-second live refresh',
    () {
      final first = NeptunData.parse(fixture(now));
      final fiveSecondsLater = NeptunData.parse(
        fixture(now.add(const Duration(seconds: 5))),
      );
      final thirtySecondsLater = NeptunData.parse(
        fixture(now.add(const Duration(seconds: 30))),
      );
      expect(shouldPersistNeptunCache(null, first), isTrue);
      expect(shouldPersistNeptunCache(first, fiveSecondsLater), isFalse);
      expect(shouldPersistNeptunCache(first, thirtySecondsLater), isTrue);

      final changedState = fixture(now.add(const Duration(seconds: 5)));
      changedState['live']['state'] = 'STALE';
      expect(
        shouldPersistNeptunCache(first, NeptunData.parse(changedState)),
        isTrue,
      );
    },
  );

  test(
    'NEPTUN last-known-good survives failure and clear removes it',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repository = DataRepository(
        prefs,
        client: MockClient((r) async {
          expect(r.url.path, '/v1/neptun');
          return jsonResponse(fixture(now), 200);
        }),
        buildApi: 'https://example.test',
      );
      await repository.refreshNeptun();
      expect(repository.cachedNeptun()?.tracks.length, 1);

      final restarted = DataRepository(
        prefs,
        client: MockClient((_) async => jsonResponse({}, 503)),
        buildApi: 'https://example.test',
      );
      await expectLater(restarted.refreshNeptun(), throwsA(isA<ApiFailure>()));
      expect(restarted.cachedNeptun()?.tracks.length, 1);
      await restarted.clearData();
      expect(restarted.cachedNeptun(), isNull);
    },
  );

  testWidgets('NEPTUN screen shows live threats, attribution and history', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repository = DataRepository(
      prefs,
      client: MockClient(
        (_) async => jsonResponse(fixture(DateTime.now().toUtc()), 200),
      ),
      buildApi: 'https://example.test',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: NeptunScreen(
          repository: repository,
          openSource: (_) {},
          showMap: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('NEPTUN'), findsOneWidget);
    expect(find.textContaining('LIVE • 1 aktywnych wpisów'), findsOneWidget);
    expect(find.text('FPV / dron'), findsOneWidget);
    expect(find.textContaining('Dane live: NEPTUN'), findsOneWidget);
    expect(find.text('Historyczny ślad testowy'), findsOneWidget);
    expect(find.text('Timeline i źródła'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
