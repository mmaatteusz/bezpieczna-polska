import 'dart:convert';

import 'package:bezpieczna_polska/model.dart';
import 'package:bezpieczna_polska/watched_locations_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> eventFixture() => {
  'id': 'around-event',
  'title': 'Zdarzenie w pobliżu',
  'description': 'Oficjalny komunikat testowy.',
  'eventType': 'RESCUE',
  'severity': 'NORMAL',
  'verification': 'CONFIRMED',
  'lifecycle': 'ACTIVE',
  'messageContext': 'ACTUAL',
  'regions': ['04'],
  'geographicScope': 'REGIONAL',
  'publishedAt': '2026-09-22T05:30:00Z',
  'publicationDate': '2026-09-22',
  'retrievedAt': '2026-09-22T05:31:00Z',
  'validFrom': '2026-09-22T05:00:00Z',
  'validTo': '2026-09-22T08:00:00Z',
  'sources': [
    {
      'id': 'RCB',
      'name': 'RCB',
      'url': 'https://www.gov.pl/web/rcb/',
      'tier': 1,
    },
  ],
  'instructions': <String>[],
  'officialWarning': true,
  'reviewed': false,
  'revision': 1,
  'correction': null,
  'latitude': 53.123,
  'longitude': 18.008,
  'geometry': {
    'type': 'Point',
    'coordinates': [18.008, 53.123],
  },
  'locationText': 'Bydgoszcz',
  'areaPrecision': 'EXACT',
  'adapterVersion': 'fixture',
  'sourceContentHash': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'isDemo': false,
};

Map<String, dynamic> aroundFixture() => {
  'schemaVersion': 1,
  'serverTime': '2026-09-22T06:00:00Z',
  'query': {
    'latitude': 53.12,
    'longitude': 18.01,
    'radiusKm': 20.0,
    'regionId': '04',
  },
  'nearbyEvents': [
    {
      'event': eventFixture(),
      'distanceMeters': 350,
      'relevance': 'NEARBY',
    },
  ],
  'regionalEvents': <dynamic>[],
  'nearestShelters': {'items': <dynamic>[], 'health': null},
  'coverage': {
    'spatial': 'PARTIAL_GEOMETRY_ONLY',
    'regional': 'EXPLICIT_NATIONAL_OR_PROVINCE_SCOPE_ONLY',
    'statement':
        'Brak geometrii nie jest interpretowany jako brak zdarzeń w pobliżu.',
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('watched locations persist locally without movement history metadata', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = DataRepository(prefs);

    final saved = await repo.addWatchedLocation(
      label: 'Dom',
      latitude: 53.12,
      longitude: 18.01,
      radiusKm: 15,
      regionId: '04',
    );

    expect(saved.id, 'loc-1');
    expect(repo.watchedLocations.single.label, 'Dom');
    expect(repo.watchedLocations.single.regionId, '04');
    expect(
      prefs.getKeys(),
      containsAll(<String>[
        DataRepository.watchedLocationsKey,
        'watched_location_counter',
      ]),
    );
    expect(
      prefs.getKeys().where(
        (k) =>
            k.contains('history') ||
            k.contains('track') ||
            k.contains('last_position'),
      ),
      isEmpty,
    );

    await repo.clearData();
    expect(repo.watchedLocations.single.label, 'Dom');

    await repo.removeWatchedLocation(saved.id);
    expect(repo.watchedLocations, isEmpty);
  });

  test('watched location validation rejects unsafe values', () async {
    final repo = DataRepository(await SharedPreferences.getInstance());
    await expectLater(
      repo.addWatchedLocation(
        label: '',
        latitude: 53,
        longitude: 18,
      ),
      throwsFormatException,
    );
    await expectLater(
      repo.addWatchedLocation(
        label: 'Poza zakresem',
        latitude: 91,
        longitude: 18,
      ),
      throwsFormatException,
    );
    await expectLater(
      repo.addWatchedLocation(
        label: 'Zły region',
        latitude: 53,
        longitude: 18,
        regionId: 'PL',
      ),
      throwsFormatException,
    );
  });

  test('coordinates are sent only when around is explicitly requested', () async {
    var requests = 0;
    final repo = DataRepository(
      await SharedPreferences.getInstance(),
      buildApi: 'https://api.example',
      developerSettingsEnabled: false,
      client: MockClient((request) async {
        requests++;
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/around');
        expect(request.url.query, isEmpty);
        final body = Map<String, dynamic>.from(
          jsonDecode(request.body) as Map,
        );
        expect(body, {
          'latitude': 53.12,
          'longitude': 18.01,
          'radiusKm': 20.0,
          'regionId': '04',
        });
        return http.Response(
          jsonEncode(aroundFixture()),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await repo.addWatchedLocation(
      label: 'Rodzina',
      latitude: 53.12,
      longitude: 18.01,
      regionId: '04',
    );
    expect(requests, 0, reason: 'saving a place must not contact the backend');

    final result = await repo.around(
      53.12,
      18.01,
      radiusKm: 20,
      regionId: '04',
    );
    expect(requests, 1);
    expect(result.nearbyEvents.single.distanceMeters, 350);
    expect(result.nearbyEvents.single.event.id, 'around-event');
    expect(result.regionId, '04');
  });

  test('around parser rejects claimed distance without event geometry', () {
    final bad = aroundFixture();
    final row = Map<String, dynamic>.from(
      (bad['nearbyEvents'] as List).single as Map,
    );
    final event = Map<String, dynamic>.from(row['event'] as Map)
      ..['latitude'] = null
      ..['longitude'] = null
      ..['geometry'] = null;
    row['event'] = event;
    bad['nearbyEvents'] = [row];
    expect(() => AroundResult.parse(bad), throwsFormatException);
  });

  testWidgets('watched locations screen explains privacy and shows saved place', (
    tester,
  ) async {
    final repo = DataRepository(await SharedPreferences.getInstance());
    await repo.addWatchedLocation(
      label: 'Praca',
      latitude: 53.13,
      longitude: 18.02,
      radiusKm: 10,
      regionId: '04',
    );

    await tester.pumpWidget(
      MaterialApp(home: WatchedLocationsScreen(repository: repo)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Wokół mnie'), findsWidgets);
    expect(find.text('Praca'), findsOneWidget);
    expect(find.textContaining('nie uruchamia ciągłego śledzenia'), findsOneWidget);
    expect(find.text('Sprawdź wokół mnie • 20 km'), findsOneWidget);
    expect(find.text('Dodaj miejsce ręcznie'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
