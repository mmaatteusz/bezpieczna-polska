import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bezpieczna_polska/model.dart';
import 'package:bezpieczna_polska/map_layers.dart';

import 'national_map_alerts_test.dart' show eventFixture;

Map<String, dynamic> data({String region = '04'}) {
  final status = {
    'displayText': 'Brak aktywnych ostrzeżeń',
    'hazardLevel': 'NO_ACTIVE_WARNINGS',
    'validUntil': '2026-09-18T10:01:00Z',
  };
  return {
    'schemaVersion': 1,
    'serverTime': '2026-09-18T10:00:00Z',
    'regionId': region,
    'status': status,
    'nationalStatus': status,
    'events': [],
    'sources': [],
  };
}

http.Response response(Map<String, dynamic> d) => http.Response(
  jsonEncode(d),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'fresh install defaults to national scope until locality is chosen',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final repository = DataRepository(
        prefs,
        buildApi: 'https://api.example.org',
      );
      expect(repository.region, 'PL');
    },
  );
  test('alert cards are stable for the lifetime of one snapshot', () {
    final snapshot = Snapshot.parse(jsonEncode(data()));
    expect(identical(snapshot.alertEvents, snapshot.alertEvents), isTrue);
  });
  testWidgets('map and home share a slow national snapshot request', (
    tester,
  ) async {
    final reply = Completer<http.Response>();
    var requests = 0;
    final repo = DataRepository(
      await SharedPreferences.getInstance(),
      buildApi: 'https://api.example.org',
      client: MockClient((_) {
        requests++;
        return reply.future;
      }),
    );
    final home = repo.refresh('PL');
    final map = repo.refresh('PL');
    final both = Future.wait([home, map]);
    var finished = false;
    unawaited(both.then((_) => finished = true));

    await tester.pump(const Duration(seconds: 18));
    expect(requests, 1);
    expect(finished, isFalse);

    reply.complete(response(data(region: 'PL')));
    await tester.pump();
    final snapshots = await both;
    expect(snapshots.first, same(snapshots.last));
    expect(repo.cached('PL')?.region, 'PL');
    await repo.refresh('PL');
    expect(requests, 2);
  });
  test(
    'national compact snapshot restores an incident and its map marker',
    () async {
      final now = DateTime.utc(2026, 11, 22, 1);
      final event = eventFixture(
        id: 'imgw-1',
        regions: ['22'],
        sourceId: 'IMGW_METEO',
        validTo: now.add(const Duration(hours: 2)),
      );
      final compact = {
        ...data(region: 'PL'),
        'snapshotMode': 'compact',
        'omittedSections': ['incidentReports', 'shelterItems'],
        'events': [event.data],
        'incidents': [
          {
            'id': 'incident-1',
            'revision': 2,
            'primaryEventId': 'imgw-1',
            'relatedEventIds': ['imgw-1'],
            'hasConflictingReports': false,
          },
        ],
      };
      final repo = DataRepository(
        await SharedPreferences.getInstance(),
        buildApi: 'https://api.example.org',
        client: MockClient((request) async {
          expect(request.url.queryParameters, {
            'regionId': 'PL',
            'mode': 'compact',
          });
          return response(compact);
        }),
      );
      final snapshot = await repo.refresh('PL');
      final alert = snapshot.alertEvents.single;
      expect(alert.incidentId, 'incident-1');
      expect(alert.reports.single.id, 'imgw-1');
      expect(
        mapEventFeatures(alert, now).single['properties']['regionId'],
        '22',
      );
      expect(repo.cached('PL')!.alertEvents.single.id, 'imgw-1');
      expect(
        () => Snapshot.parse(jsonEncode({...compact, 'snapshotMode': 'full'})),
        throwsFormatException,
      );
    },
  );
  test(
    'stale data never presents current green',
    () => expect(
      Snapshot.parse(
        jsonEncode(data()),
      ).statusText(DateTime.parse('2026-09-18T10:02:00Z'), online: true),
      'Brak bieżącej oceny sytuacji',
    ),
  );
  test(
    'offline immediately invalidates current status',
    () => expect(
      Snapshot.parse(
        jsonEncode(data()),
      ).statusText(DateTime.parse('2026-09-18T10:00:10Z'), online: false),
      'Brak bieżącej oceny sytuacji',
    ),
  );
  test(
    'future server clock is not trusted',
    () => expect(
      Snapshot.parse(
        jsonEncode(data()),
      ).freshAt(DateTime.parse('2026-09-17T10:00:00Z')),
      false,
    ),
  );
  test('API only allows HTTPS without credentials or query', () {
    for (final u in [
      'http://api.example',
      'https://user:pass@api.example',
      'https://api.example?key=x',
      'file:///tmp',
    ]) {
      expect(() => DataRepository.validateApi(u), throwsFormatException);
    }
  });
  test(
    'refresh persists valid region-specific copy with Polish text',
    () async {
      final p = await SharedPreferences.getInstance();
      final r = DataRepository(
        p,
        client: MockClient((q) async {
          expect(q.url.queryParameters['regionId'], '04');
          return response(data());
        }),
      );
      await r.setDeveloperApi('https://api.example');
      await r.refresh('04');
      expect(r.cached('04')?.region, '04');
      expect(r.cached('06'), null);
    },
  );
  test('malformed response preserves last valid cache', () async {
    final p = await SharedPreferences.getInstance();
    final r = DataRepository(
      p,
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    await r.setDeveloperApi('https://api.example');
    await p.setString(r.cacheKey('04'), jsonEncode(data()));
    await expectLater(r.refresh('04'), throwsA(anything));
    expect(r.cached('04'), isNotNull);
  });
  test('wrong region is rejected before caching', () async {
    final p = await SharedPreferences.getInstance();
    final r = DataRepository(
      p,
      client: MockClient((_) async => response(data(region: '06'))),
    );
    await r.setDeveloperApi('https://api.example');
    await expectLater(r.refresh('04'), throwsFormatException);
    expect(r.cached('04'), null);
  });
  test('server changes do not reuse another server cache', () async {
    final p = await SharedPreferences.getInstance();
    final r = DataRepository(p);
    await r.setDeveloperApi('https://one.example');
    await p.setString(r.cacheKey('04'), jsonEncode(data()));
    await r.setDeveloperApi('https://two.example');
    expect(r.cached('04'), null);
  });
  test('corrupt disk cache fails closed', () async {
    final p = await SharedPreferences.getInstance();
    final r = DataRepository(p);
    await p.setString(r.cacheKey('04'), 'broken');
    expect(r.cached('04'), null);
  });
  test('clear retains configuration', () async {
    final r = DataRepository(await SharedPreferences.getInstance());
    await r.setRegion('06');
    await r.prefs.setString(r.cacheKey('06'), jsonEncode(data(region: '06')));
    await r.clearData();
    expect(r.region, '06');
    expect(r.cached('06'), null);
  });
  test('clear rejects an in-flight response', () async {
    final pending = Completer<http.Response>();
    final r = DataRepository(
      await SharedPreferences.getInstance(),
      client: MockClient((_) => pending.future),
    );
    await r.setDeveloperApi('https://api.example');
    final rejected = expectLater(r.refresh('04'), throwsStateError);
    await r.clearData();
    pending.complete(response(data()));
    await rejected;
    expect(r.cached('04'), null);
  });
  test('national status is validated', () {
    final d = data()..['nationalStatus'] = {'displayText': 12};
    expect(() => Snapshot.parse(jsonEncode(d)), throwsFormatException);
  });

  test(
    'production uses build URL and ignores all persisted overrides',
    () async {
      SharedPreferences.setMockInitialValues({
        'api': 'https://legacy.example',
        'developer_api': 'https://debug.example',
      });
      final r = DataRepository(
        await SharedPreferences.getInstance(),
        buildApi: 'https://build.example/',
        developerSettingsEnabled: false,
      );
      expect(r.api, 'https://build.example');
      await expectLater(
        r.setDeveloperApi('https://override.example'),
        throwsStateError,
      );
    },
  );
  test('developer override can be reset to build URL', () async {
    final r = DataRepository(
      await SharedPreferences.getInstance(),
      buildApi: 'https://build.example',
      developerSettingsEnabled: true,
    );
    await r.setDeveloperApi('https://override.example');
    expect(r.api, 'https://override.example');
    await r.setDeveloperApi('');
    expect(r.api, 'https://build.example');
  });
  test(
    'build URL retrieves real API contract without setting preferences',
    () async {
      final r = DataRepository(
        await SharedPreferences.getInstance(),
        buildApi: 'https://build.example',
        developerSettingsEnabled: false,
        client: MockClient((request) async {
          expect(request.url.host, 'build.example');
          expect(request.url.path, '/v1/snapshot');
          return response(data());
        }),
      );
      expect((await r.refresh('04')).region, '04');
    },
  );
}
