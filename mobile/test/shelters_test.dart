import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bezpieczna_polska/model.dart';
import 'package:bezpieczna_polska/shelters.dart';
import 'package:bezpieczna_polska/shelter_panel.dart';

Map<String, dynamic> fixture() =>
    jsonDecode(File('test/fixtures/shelters.json').readAsStringSync())
        as Map<String, dynamic>;
http.Response response(Map<String, dynamic> m) => http.Response(
  jsonEncode(m),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'real PSP sample: no invented protection, opening hours or freshness',
    () {
      final p = ShelterPage.parse(fixture());
      expect(p.items.first.address, 'ul. Kormoranów 54, Bydgoszcz');
      expect(p.items[1].availability, contains('godzin nie podano'));
      expect(p.freshAt(DateTime.parse('2026-09-19T12:30:00Z')), isTrue);
      expect(p.freshAt(DateTime.parse('2026-09-22T12:30:00Z')), isFalse);
      final wrong = fixture();
      wrong['items'][0]['latitude'] = 18;
      expect(() => ShelterPage.parse(wrong), throwsFormatException);
      expect(
        () => ShelterPage.parse({...fixture(), 'regionId': '02'}),
        throwsFormatException,
      );
      expect(
        () => ShelterPage.parse({...fixture(), 'hasMore': true}),
        throwsFormatException,
      );
    },
  );

  test(
    'build URL, region and query isolation; bounded cache and clear invalidation',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final pending = Completer<http.Response>();
      var delay = false;
      final r = DataRepository(
        prefs,
        buildApi: 'https://build.example',
        client: MockClient((request) async {
          expect(request.url.path, '/v1/shelters');
          expect(request.url.queryParameters['regionId'], '04');
          expect(request.url.queryParameters['q'], 'Bydgoszcz');
          return delay ? pending.future : response(fixture());
        }),
      );
      await r.refreshShelters('04', query: ' Bydgoszcz ');
      expect(r.cachedShelters('04')?.items.length, 3);
      expect(r.cachedShelters('02'), isNull);
      final other = DataRepository(prefs, buildApi: 'https://other.example');
      expect(other.cachedShelters('04'), isNull);
      delay = true;
      final late = r.refreshShelters('04', query: 'Bydgoszcz');
      final assertion = expectLater(late, throwsStateError);
      await r.clearData();
      pending.complete(response(fixture()));
      await assertion;
      expect(r.cachedShelters('04'), isNull);
    },
  );

  test(
    'failed response keeps the last good page; version conflict is explicit',
    () async {
      final prefs = await SharedPreferences.getInstance();
      var mode = 0;
      final r = DataRepository(
        prefs,
        buildApi: 'https://build.example',
        client: MockClient(
          (_) async => switch (mode) {
            1 => http.Response('{}', 409),
            2 => response({...fixture(), 'query': 'wrong'}),
            _ => response(fixture()),
          },
        ),
      );
      await r.refreshShelters('04', query: 'Bydgoszcz');
      mode = 1;
      await expectLater(
        r.refreshShelters(
          '04',
          query: 'Bydgoszcz',
          offset: 50,
          version: 'a' * 64,
        ),
        throwsA(isA<ShelterVersionChanged>()),
      );
      mode = 2;
      await expectLater(
        r.refreshShelters('04', query: 'Bydgoszcz'),
        throwsFormatException,
      );
      expect(r.cachedShelters('04')?.query, 'Bydgoszcz');
    },
  );

  test(
    'nearest shelter response validates ordering and repository request',
    () async {
      final raw = fixture(),
          first = Map<String, dynamic>.from(
            (raw['items'] as List).first as Map,
          );
      final result = {
        'schemaVersion': 1,
        'serverTime': '2026-09-19T12:00:00Z',
        'query': {
          'latitude': first['latitude'],
          'longitude': first['longitude'],
        },
        'health': raw['health'],
        'items': [
          {'point': first, 'distanceMeters': 0},
          {
            'point': Map<String, dynamic>.from(
              (raw['items'] as List)[1] as Map,
            ),
            'distanceMeters': 550,
          },
        ],
      };
      final parsed = NearestSheltersResult.parse(result);
      expect(parsed.items.first.distanceLabel, '0 m');
      expect(parsed.items[1].distanceLabel, '550 m');
      expect(
        () => NearestSheltersResult.parse({
          ...result,
          'items': [
            {'point': first, 'distanceMeters': 500},
            {
              'point': Map<String, dynamic>.from(
                (raw['items'] as List)[1] as Map,
              ),
              'distanceMeters': 100,
            },
          ],
        }),
        throwsFormatException,
      );
      final repo = DataRepository(
        await SharedPreferences.getInstance(),
        buildApi: 'https://build.example',
        client: MockClient((request) async {
          expect(request.url.path, '/v1/shelters/nearest');
          expect(
            request.url.queryParameters['lat'],
            first['latitude'].toString(),
          );
          expect(
            request.url.queryParameters['lon'],
            first['longitude'].toString(),
          );
          expect(request.url.queryParameters['limit'], '3');
          return response(result);
        }),
      );
      final fetched = await repo.nearestShelters(
        first['latitude'] as double,
        first['longitude'] as double,
      );
      expect(fetched.items.first.point.id, first['id']);
    },
  );

  testWidgets(
    'offline results, availability and search preserve phone layout at 200%',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final prefs = await SharedPreferences.getInstance();
      final r = DataRepository(
        prefs,
        buildApi: 'https://build.example',
        client: MockClient((_) async => response(fixture())),
      );
      await r.refreshShelters('04', query: 'Bydgoszcz');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: SingleChildScrollView(
                child: ShelterPanel(
                  repository: r,
                  region: '04',
                  initial: null,
                  online: false,
                  openLink: (_) async {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        find.text('Kopia zapisana — aktualność niepotwierdzona'),
        findsOneWidget,
      );
      expect(find.text('ul. Kormoranów 54, Bydgoszcz'), findsOneWidget);
      expect(
        find.textContaining('Określone godziny — godzin nie podano'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Szukaj punktów'));
      await tester.tap(find.text('Szukaj punktów'));
      await tester.pumpAndSettle();
      expect(find.text('Wyszukiwanie: Bydgoszcz'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
