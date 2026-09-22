import 'dart:convert';

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
    'schemaVersion': 1,
    'mode': 'HISTORICAL_ONLY',
    'serverTime': now.toIso8601String(),
    'safetyDelayHours': 24,
    'minimumPublishedPrecisionKm': 10,
    'coverage': 'CURATED_HISTORY',
    'sourceHealth': null,
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
  final now = DateTime.utc(2026, 9, 22, 12);

  test('NEPTUN parser accepts only historical coarse tracks', () {
    final data = NeptunData.parse(fixture(now));
    expect(data.tracks.length, 1);
    expect(data.tracks.first['lifecycle'], 'ENDED');

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
  });

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

  testWidgets('NEPTUN screen is explicitly historical and shows sources', (
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
    expect(
      find.textContaining('Historyczny przebieg zdarzeń OSINT'),
      findsOneWidget,
    );
    expect(
      find.textContaining('nie pokazuje aktywnych dokładnych pozycji'),
      findsOneWidget,
    );
    expect(find.text('Historyczny ślad testowy'), findsOneWidget);
    expect(find.text('Timeline i źródła'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
