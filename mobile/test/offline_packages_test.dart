import 'dart:convert';

import 'package:bezpieczna_polska/main.dart';
import 'package:bezpieczna_polska/model.dart';
import 'package:bezpieczna_polska/offline_data_screen.dart';
import 'package:bezpieczna_polska/offline_packages.dart';
import 'package:bezpieczna_polska/offline_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const version =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Map<String, dynamic> source({String id = 'RCB', String state = 'HEALTHY'}) => {
  'id': id,
  'name': id == 'SHELTERS' ? 'Punkty schronienia PSP' : id,
  'url': 'https://example.invalid/$id',
  'state': state,
  'healthStatus': state,
  'maxAgeSeconds': 3600,
  'complete': true,
  'lastSuccess': '2026-09-22T10:00:00Z',
  'lastItemTime': '2026-09-22T10:00:00Z',
  'sourceUpdatedAt': '2026-09-22T09:00:00Z',
  'dataDate': '2026-09-22',
};

Map<String, dynamic> event() => {
  'id': 'offline-event',
  'title': 'Zdarzenie testowe',
  'description': 'Opis',
  'eventType': 'RESCUE',
  'severity': 'NORMAL',
  'verification': 'CONFIRMED',
  'lifecycle': 'ACTIVE',
  'messageContext': 'ACTUAL',
  'regions': ['04'],
  'sources': [
    {
      'id': 'RCB',
      'name': 'RCB',
      'url': 'https://example.invalid/rcb',
      'tier': 1,
    },
  ],
  'revision': 1,
  'latitude': 53.12,
  'longitude': 18.01,
  'geometry': {
    'type': 'Point',
    'coordinates': [18.01, 53.12],
  },
};

Map<String, dynamic> snapshot({
  String region = '04',
  String sourceState = 'HEALTHY',
}) {
  final status = {
    'displayText': 'Brak aktywnych ostrzeżeń w monitorowanych źródłach',
    'hazardLevel': 'NO_ACTIVE_WARNINGS',
    'validUntil': '2026-09-22T10:30:00Z',
  };
  return {
    'schemaVersion': 1,
    'serverTime': '2026-09-22T10:00:00Z',
    'releaseStage': 'ALPHA',
    'regionId': region,
    'status': status,
    'nationalStatus': status,
    'events': [event()],
    'incidents': <dynamic>[],
    'sources': [
      source(state: sourceState),
      source(id: 'SHELTERS', state: sourceState),
    ],
    'sourceHealth': [
      source(state: sourceState),
      source(id: 'SHELTERS', state: sourceState),
    ],
    'securityLevels': <dynamic>[],
    'nationalSecurityLevels': <dynamic>[],
    'ukraineAlerts': <dynamic>[],
  };
}

Map<String, dynamic> shelter({String id = 's-1', String region = '04'}) => {
  'id': id,
  'address': 'ul. Testowa 1, Bydgoszcz',
  'municipality': 'Bydgoszcz',
  'county': 'Bydgoszcz',
  'regionId': region,
  'sourceType': 'MDS',
  'sourceAvailability': 'UNKNOWN',
  'dataDate': '2026-09-22',
  'sourceUpdatedAt': '2026-09-22T09:00:00Z',
  'sourceId': 'SHELTERS',
  'category': 'SHELTER_POINT',
  'protectionClass': 'UNKNOWN',
  'availability': 'UNKNOWN',
  'latitude': 53.121,
  'longitude': 18.011,
};

Map<String, dynamic> shelterPage({String region = '04'}) => {
  'schemaVersion': 1,
  'serverTime': '2026-09-22T10:00:00Z',
  'regionId': region,
  'query': '',
  'items': [shelter(region: region)],
  'total': 1,
  'offset': 0,
  'limit': 500,
  'hasMore': false,
  'version': version,
  'health': source(id: 'SHELTERS'),
};

http.Response ok(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

MockClient downloadClient({String sourceState = 'HEALTHY'}) => MockClient((
  request,
) async {
  switch (request.url.path) {
    case '/v1/snapshot':
      return ok(
        snapshot(
          region: request.url.queryParameters['regionId'] ?? '04',
          sourceState: sourceState,
        ),
      );
    case '/healthz':
      return ok({'ok': true, 'version': '0.1.0-alpha.15'});
    case '/v1/shelters':
      return ok(
        shelterPage(region: request.url.queryParameters['regionId'] ?? '04'),
      );
    default:
      return http.Response('{}', 404);
  }
});

Future<DataRepository> repoWithDownload({
  SharedPreferences? prefs,
  String sourceState = 'HEALTHY',
}) async => DataRepository(
  prefs ?? await SharedPreferences.getInstance(),
  buildApi: 'https://api.example',
  developerSettingsEnabled: false,
  client: downloadClient(sourceState: sourceState),
);

OfflineRegionPackage package({
  String region = '04',
  DateTime? createdAt,
  String sourceState = 'HEALTHY',
}) => OfflineRegionPackage.create(
  regionId: region,
  createdAt: createdAt ?? DateTime.parse('2026-09-22T10:01:00Z'),
  snapshotTimestamp: DateTime.parse('2026-09-22T10:00:00Z'),
  snapshot: snapshot(region: region, sourceState: sourceState),
  shelters: [shelter(region: region)],
  watchedLocations: const [],
  sourceTimestamps: {
    'RCB': {'state': sourceState, 'lastSuccess': '2026-09-22T10:00:00Z'},
  },
  components: const [
    'status',
    'events',
    'incidents',
    'sourceHealth',
    'securityLevels',
    'radiation',
    'shelters',
    'watchedLocations',
    'mapOverlays',
  ],
  layers: const ['shelters-local', 'events-local'],
  shelterVersion: version,
  backendVersion: '0.1.0-alpha.15',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('download region package validates and atomically activates', () async {
    final repo = await repoWithDownload();
    final result = await repo.downloadOfflinePackage('04');
    expect(result.regionId, '04');
    expect(result.shelters.single['id'], 's-1');
    expect((await repo.listOfflinePackages()).single.package, isNotNull);
  });

  test('new offline payload is file-backed and uses SHA-256', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = OfflinePackageStore(prefs);
    final value = package();
    await store.commit(value);
    final pointer = prefs.getString('offline_package_active_v1:04');
    expect(pointer, isNotNull);
    expect(prefs.getString(pointer!), isNull);
    expect((await store.debugReadActiveRaw('04')), isNotNull);
    expect(value.manifest['checksum']['algorithm'], 'SHA-256');
  });

  test(
    'legacy SharedPreferences payload is lazily migrated without losing LKG',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final legacy = package();
      const pointer = 'offline_package_data_v1:04:legacy';
      await prefs.setString('offline_package_active_v1:04', pointer);
      await prefs.setString(pointer, legacy.encode());

      final store = OfflinePackageStore(prefs);
      final loaded = await store.load('04');
      expect(loaded?.regionId, '04');
      expect(prefs.getString(pointer), isNull);
      expect(await store.debugReadActiveRaw('04'), isNotNull);
    },
  );

  test('failed refresh preserves previous package', () async {
    final prefs = await SharedPreferences.getInstance();
    final good = await repoWithDownload(prefs: prefs);
    final first = await good.downloadOfflinePackage('04');
    final broken = DataRepository(
      prefs,
      buildApi: 'https://api.example',
      developerSettingsEnabled: false,
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    await expectLater(
      broken.downloadOfflinePackage('04'),
      throwsA(isA<ApiFailure>()),
    );
    final still = await broken.offlinePackage('04');
    expect(still?.manifest['checksum'], first.manifest['checksum']);
  });

  test('restart keeps active package and discards no valid LKG', () async {
    final prefs = await SharedPreferences.getInstance();
    final first = await repoWithDownload(prefs: prefs);
    await first.downloadOfflinePackage('04');
    final restarted = DataRepository(prefs);
    expect((await restarted.offlinePackage('04'))?.regionId, '04');
  });

  test('corrupted refresh falls back to previous validated LKG', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = OfflinePackageStore(prefs);
    final first = package(createdAt: DateTime.parse('2026-09-22T10:01:00Z'));
    final second = package(createdAt: DateTime.parse('2026-09-22T10:02:00Z'));
    await store.commit(first);
    await store.commit(second);

    final decoded =
        jsonDecode((await store.debugReadActiveRaw('04'))!)
            as Map<String, dynamic>;
    final manifest = Map<String, dynamic>.from(decoded['manifest'] as Map);
    manifest['checksum'] = {'algorithm': 'SHA-256', 'value': '00'};
    decoded['manifest'] = manifest;
    await store.debugOverwriteActiveRaw('04', jsonEncode(decoded));

    final listed = await store.list();
    expect(listed.single.state, OfflinePackageState.corrupted);
    final recovered = await store.load('04');
    expect(recovered?.createdAt, first.createdAt);
  });

  test('corrupted package is marked and never returned as usable', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = OfflinePackageStore(prefs);
    await store.commit(package());
    final envelope =
        jsonDecode((await store.debugReadActiveRaw('04'))!)
            as Map<String, dynamic>;
    (envelope['payload'] as Map)['watchedLocations'] = [
      {'id': 'tampered'},
    ];
    await store.debugOverwriteActiveRaw('04', jsonEncode(envelope));
    final listed = await store.list();
    expect(listed.single.state, OfflinePackageState.corrupted);
    await expectLater(
      store.load('04'),
      throwsA(isA<OfflinePackageException>()),
    );
  });

  test('checksum mismatch is rejected', () {
    final decoded = jsonDecode(package().encode()) as Map<String, dynamic>;
    final manifest = Map<String, dynamic>.from(decoded['manifest'] as Map);
    manifest['checksum'] = {'algorithm': 'CRC32', 'value': '00000000'};
    decoded['manifest'] = manifest;
    expect(
      () => OfflineRegionPackage.parse(jsonEncode(decoded)),
      throwsA(
        isA<OfflinePackageException>().having(
          (e) => e.code,
          'code',
          'CHECKSUM_MISMATCH',
        ),
      ),
    );
  });

  test(
    'unsupported schema requires refresh instead of migration guess',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = OfflinePackageStore(prefs);
      await store.commit(package());
      final decoded =
          jsonDecode((await store.debugReadActiveRaw('04'))!)
                as Map<String, dynamic>
            ..['schemaVersion'] = 99;
      await store.debugOverwriteActiveRaw('04', jsonEncode(decoded));
      final listed = await store.list();
      expect(listed.single.state, OfflinePackageState.refreshRequired);
    },
  );

  test('incomplete active package is fail-closed', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'offline_package_active_v1:04',
      'offline_package_data_v1:04:missing',
    );
    final listed = await OfflinePackageStore(prefs).list();
    expect(listed.single.state, OfflinePackageState.incomplete);
  });

  test('stale package remains LKG but is never LIVE', () {
    final p = package(createdAt: DateTime.parse('2026-09-22T09:00:00Z'));
    expect(
      p.stateAt(DateTime.parse('2026-09-22T11:00:00Z')),
      OfflinePackageState.stale,
    );
    final parsed = Snapshot.parse(jsonEncode(p.snapshot));
    expect(
      parsed.statusText(DateTime.parse('2026-09-22T10:01:00Z'), online: false),
      'Brak bieżącej oceny sytuacji',
    );
  });

  test('sourceHealth DOWN is preserved in package metadata', () {
    final p = package(sourceState: 'BROKEN');
    final sourceMap = p.manifest['sourceTimestamps'] as Map;
    expect((sourceMap['RCB'] as Map)['state'], 'BROKEN');
  });

  test('delete removes only selected region package', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = OfflinePackageStore(prefs);
    await store.commit(package(region: '04'));
    await store.commit(package(region: '06'));
    await store.delete('04');
    expect(await store.load('04'), isNull);
    expect((await store.load('06'))?.regionId, '06');
  });

  test('package count limit evicts LRU but keeps newest package', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = OfflinePackageStore(prefs);
    for (final region in ['02', '04', '06', '08', '10', '12', '14']) {
      await store.commit(package(region: region));
    }
    final list = await store.list();
    expect(list.length, lessThanOrEqualTo(OfflinePackageStore.maxPackages));
    expect(list.any((item) => item.regionId == '14'), isTrue);
  });

  test('offline shelter search uses complete package after restart', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = await repoWithDownload(prefs: prefs);
    await repo.downloadOfflinePackage('04');
    final restarted = DataRepository(prefs);
    final page = await restarted.offlineShelterPage('04', query: 'Bydgoszcz');
    expect(page?.items.single.address, contains('Testowa'));
    expect(page?.health?['healthStatus'], 'STALE');
  });

  test('nearest shelter is calculated locally from package', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = await repoWithDownload(prefs: prefs);
    await repo.downloadOfflinePackage('04');
    final offline = DataRepository(prefs);
    final result = await offline.offlineNearestShelters(
      53.12,
      18.01,
      regionId: '04',
    );
    expect(result?.items.single.point.id, 's-1');
    expect(result?.health?['healthStatus'], 'STALE');
  });

  test(
    'around offline uses package timestamp and no network request',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = await repoWithDownload(prefs: prefs);
      await repo.downloadOfflinePackage('04');
      var requests = 0;
      final offline = DataRepository(
        prefs,
        buildApi: 'https://api.example',
        client: MockClient((_) async {
          requests++;
          throw http.ClientException('must not be called');
        }),
      );
      final result = await offline.offlineAround(53.12, 18.01, regionId: '04');
      expect(requests, 0);
      expect(result?.nearbyEvents.single.event.id, 'offline-event');
      expect(result?.data['offlineSnapshotTimestamp'], isNotNull);
      expect(
        prefs.getKeys().where(
          (key) =>
              key.contains('gps_history') ||
              key.contains('last_position') ||
              key.contains('track_history'),
        ),
        isEmpty,
      );
    },
  );

  test('Ukraine data cannot enter Poland offline package', () {
    final bad = snapshot();
    (bad['events'] as List).add({
      ...event(),
      'id': 'ua',
      'countryCode': 'UA',
      'ukraine': {'regionId': '1'},
      'sources': [
        {
          'id': 'UA',
          'name': 'UA',
          'url': 'https://example.invalid/ua',
          'tier': 1,
        },
      ],
    });
    expect(
      () => OfflineRegionPackage.create(
        regionId: '04',
        createdAt: DateTime.parse('2026-09-22T10:01:00Z'),
        snapshotTimestamp: DateTime.parse('2026-09-22T10:00:00Z'),
        snapshot: bad,
        shelters: [shelter()],
        watchedLocations: const [],
        sourceTimestamps: const {},
        components: const ['status'],
        layers: const ['shelters-local'],
        shelterVersion: version,
      ),
      throwsA(isA<OfflinePackageException>()),
    );
  });

  test('NEPTUN payload is not part of region package contract', () {
    final p = package();
    expect(p.payload.containsKey('neptun'), isFalse);
    expect(
      p.components.any((item) => item.toLowerCase().contains('neptun')),
      isFalse,
    );
  });

  test('push preferences survive package commit and offline restart', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'push_preferences_v1',
      jsonEncode({'criticalPoland': false, 'ukraine': true}),
    );
    final store = OfflinePackageStore(prefs);
    await store.commit(package());
    final restarted = OfflinePackageStore(prefs);
    expect((await restarted.load('04'))?.regionId, '04');
    expect(prefs.getString('push_preferences_v1'), isNotNull);
    expect(
      jsonDecode(prefs.getString('push_preferences_v1')!)['ukraine'],
      isTrue,
    );
  });

  testWidgets('offline data screen shows package timestamp and integrity', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.runAsync(() => OfflinePackageStore(prefs).commit(package()));
    final repo = DataRepository(prefs);
    await tester.pumpWidget(
      MaterialApp(home: OfflineDataScreen(repository: repo)),
    );
    // The screen reloads file-backed packages from real async I/O. Do not use
    // pumpAndSettle while the indeterminate loading indicator is mounted:
    // fake-time pumping can starve the real file-system future indefinitely.
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
    }
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Dane offline'), findsOneWidget);
    expect(
      find.textContaining('Podkład mapy nie jest częścią pakietu'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.byType(ExpansionTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ExpansionTile).first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Snapshot danych:'), findsOneWidget);
    expect(find.textContaining('Integralność: zweryfikowana'), findsOneWidget);
    expect(find.textContaining('LAST KNOWN GOOD:'), findsOneWidget);
  });

  testWidgets('offline home never presents LKG as LIVE green status', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.runAsync(() => OfflinePackageStore(prefs).commit(package()));
    final repo = DataRepository(prefs);
    await tester.pumpWidget(SafetyApp(repository: repo));
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      if (find
          .textContaining('OFFLINE • LAST KNOWN GOOD')
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }
    expect(find.textContaining('OFFLINE • LAST KNOWN GOOD'), findsWidgets);
    expect(
      find.textContaining('Brak nowych danych nie oznacza bezpieczeństwa'),
      findsWidgets,
    );
  });
}
