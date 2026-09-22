import 'dart:convert';

import 'package:bezpieczna_polska/model.dart';
import 'package:bezpieczna_polska/ukraine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> ua(DateTime now) => {
  'schemaVersion': 1,
  'countryCode': 'UA',
  'coverage': 'partial',
  'serverTime': now.toIso8601String(),
  'lastSuccessfulSyncAt': now.toIso8601String(),
  'validUntil': now.add(const Duration(seconds: 180)).toIso8601String(),
  'sourceHealth': {'id': 'UA', 'state': 'HEALTHY', 'maxAgeSeconds': 180},
  'healthStatus': 'HEALTHY',
  'events': [
    {
      'id': 'UA-fixture',
      'title': 'Alarm powietrzny — obwód testowy',
      'description': 'Fixture',
      'countryCode': 'UA',
      'origin': 'OFFICIAL_FOREIGN',
      'regions': <String>[],
      'revision': 1,
      'lifecycle': 'ACTIVE',
      'verification': 'CONFIRMED',
      'messageContext': 'ACTUAL',
      'validFrom': null,
      'validTo': null,
      'publishedAt': null,
      'retrievedAt': now.toIso8601String(),
      'ukraine': {
        'regionId': 'fixture',
        'regionName': 'Obwód testowy',
        'regionType': 'State',
        'kind': 'OFFICIAL_ALERT',
        'sourceUpdatedAt': null,
      },
      'sources': [
        {
          'id': 'UA',
          'name': 'UkraineAlarm',
          'url': 'https://map.ukrainealarm.com/',
          'tier': 1,
        },
      ],
      'freshness': 'FRESH',
      'geometry': null,
    },
  ],
  'regions': <dynamic>[],
  'revisions': <dynamic>[],
  'map': {'type': 'FeatureCollection', 'features': <dynamic>[]},
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 9, 22, 12);
  test(
    'UA parser: times stay unknown, no guessed geometry, stale and offline',
    () {
      final d = UkraineData.parse(ua(now));
      expect(d.data['events'][0]['validFrom'], isNull);
      expect(d.freshAt(now, true), isTrue);
      expect(d.freshAt(now, false), isFalse);
      expect(d.freshAt(now.add(const Duration(seconds: 181)), true), isFalse);
      expect(d.mapAt(now, false)['features'], isEmpty);
    },
  );
  test('UA parser rejects changed contracts, Polish region and unsupported geometry', () {
    expect(
      () => UkraineData.parse({...ua(now), 'coverage': 'complete'}),
      throwsFormatException,
    );
    final bad = ua(now);
    bad['events'][0]['regions'] = ['04'];
    expect(() => UkraineData.parse(bad), throwsFormatException);
    final geo = ua(now);
    geo['map']['features'] = [
      {
        'geometry': {
          'type': 'Point',
          'coordinates': [31, 49],
        },
        'properties': {'eventId': 'UA-fixture'},
      },
    ];
    expect(() => UkraineData.parse(geo), throwsFormatException);
    final end = ua(now);
    end['events'][0]['lifecycle'] = 'ENDED';
    expect(() => UkraineData.parse(end), throwsFormatException);
  });
  test('UA map downgrades fresh polygon to STALE offline', () {
    final raw = ua(now);
    raw['map']['features'] = [
      {
        'type': 'Feature',
        'geometry': {
          'type': 'Polygon',
          'coordinates': [
            [
              [30, 48],
              [31, 48],
              [31, 49],
              [30, 48],
            ],
          ],
        },
        'properties': {'eventId': 'UA-fixture', 'freshness': 'FRESH'},
      },
    ];
    final data = UkraineData.parse(raw);
    expect(
      data.mapAt(now, true)['features'][0]['properties']['freshness'],
      'FRESH',
    );
    expect(
      data.mapAt(now, false)['features'][0]['properties']['freshness'],
      'STALE',
    );
  });
  test('UA last-known-good survives restart, failed refresh and clearing removes it', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repository = DataRepository(
      prefs,
      client: MockClient((r) async {
        expect(r.url.path, '/v1/ukraine');
        return http.Response(jsonEncode(ua(now)), 200);
      }),
      buildApi: 'https://example.test',
    );
    await repository.refreshUkraine();
    final restarted = DataRepository(
      prefs,
      client: MockClient((_) async => http.Response('{}', 503)),
      buildApi: 'https://example.test',
    );
    expect(restarted.cachedUkraine(), isNotNull);
    await expectLater(restarted.refreshUkraine(), throwsA(isA<ApiFailure>()));
    expect(restarted.cachedUkraine()!.data['events'].length, 1);
    await restarted.clearData();
    expect(restarted.cachedUkraine(), isNull);
  });
  test(
    'UA invalid response never overwrites a valid offline snapshot',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var bad = false;
      final repository = DataRepository(
        prefs,
        client: MockClient(
          (_) async => http.Response(jsonEncode(bad ? {} : ua(now)), 200),
        ),
        buildApi: 'https://example.test',
      );
      await repository.refreshUkraine();
      bad = true;
      await expectLater(
        repository.refreshUkraine(),
        throwsA(isA<ApiFailure>()),
      );
      expect(repository.cachedUkraine()!.data['events'].length, 1);
    },
  );
  testWidgets(
    'UA screen displays source health, unknown times and independent Polish status',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repository = DataRepository(
        prefs,
        client: MockClient(
          (_) async =>
              http.Response(jsonEncode(ua(DateTime.now().toUtc())), 200),
        ),
        buildApi: 'https://example.test',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: UkrainePanel(
                repository: repository,
                openSource: (_) {},
                showMap: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Status Polski jest oceniany niezależnie'),
        findsOneWidget,
      );
      expect(find.textContaining('HEALTHY'), findsOneWidget);
      expect(find.text('Rozpoczęcie: Nie podano'), findsOneWidget);
      expect(find.text('Zakończenie: Nie podano'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
