import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bezpieczna_polska/model.dart';
import 'package:bezpieczna_polska/map_layers.dart';

final request = MapRequest([17.8, 53, 18.3, 53.3], 10, '04');
Map<String, dynamic> fixture(MapRequest q) {
  final shelter =
      jsonDecode(File('test/fixtures/shelters.json').readAsStringSync())
          as Map<String, dynamic>;
  return {
    'type': 'FeatureCollection',
    'metadata': {
      'schemaVersion': 1,
      'layerId': 'shelters',
      'authority': 'OFFICIAL_PL',
      'bbox': q.query['bbox']!.split(',').map(double.parse).toList(),
      'zoom': double.parse(q.query['zoom']!),
      'regionId': q.region,
      'availability': q.availability,
      'total': shelter['items'].length,
      'returned': shelter['items'].length,
      'health': shelter['health'],
      'serverTime': shelter['serverTime'],
    },
    'features': (shelter['items'] as List)
        .map(
          (p) => {
            'type': 'Feature',
            'id': p['id'],
            'geometry': {
              'type': 'Point',
              'coordinates': [p['longitude'], p['latitude']],
            },
            'properties': {...p, 'cluster': false},
          },
        )
        .toList(),
  };
}

http.Response response(Map<String, dynamic> data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'real PSP fixture: bounded viewport, health expiry, invalid region and incomplete clusters',
    () {
      final data = fixture(request),
          v = MapViewport.parse(jsonEncode(data), request);
      expect(v.data['features'].length, 3);
      expect(v.freshAt(DateTime.parse('2026-09-19T12:30:00Z')), isTrue);
      expect(v.freshAt(DateTime.parse('2026-09-22T12:30:00Z')), isFalse);
      expect(
        () => MapViewport.parse(
          jsonEncode(data),
          MapRequest(request.bbox, 10, '02'),
        ),
        throwsFormatException,
      );
      data['metadata']['total'] = 4;
      expect(
        () => MapViewport.parse(jsonEncode(data), request),
        throwsFormatException,
      );
    },
  );
  test('shelter viewport is not limited by the selected status region', () {
    final q = shelterViewportRequest([14.0, 49.0, 24.2, 55.0], 5.2, 'ALL');
    expect(q.region, 'PL');
    expect(q.query['regionId'], 'PL');
    expect(q.bbox, [14.0, 49.0, 24.2, 55.0]);
  });

  test(
    'pan and zoom keep rendered markers but region/filter changes invalidate them',
    () {
      final rendered = MapRequest([17.8, 53, 18.3, 53.3], 10, '04', 'ALL');
      expect(
        mapDatasetChanged(
          rendered,
          MapRequest([17.9, 53.05, 18.4, 53.35], 11, '04', 'ALL'),
        ),
        isFalse,
      );
      expect(
        mapDatasetChanged(rendered, MapRequest(rendered.bbox, 10, '14', 'ALL')),
        isTrue,
      );
      expect(
        mapDatasetChanged(rendered, MapRequest(rendered.bbox, 10, '04', '24H')),
        isTrue,
      );
    },
  );

  test(
    'backend bbox/filter sent automatically; offline retains last known good only for same viewport',
    () async {
      var fail = false;
      final repo = DataRepository(
        await SharedPreferences.getInstance(),
        buildApi: 'https://build.example',
        client: MockClient((r) async {
          expect(r.url.path, '/v1/map/shelters');
          expect(r.url.queryParameters, request.query);
          if (fail) throw Exception('offline');
          return response(fixture(request));
        }),
      );
      final provider = ShelterMapProvider(repo);
      await provider.fetch(request);
      fail = true;
      await expectLater(provider.fetch(request), throwsException);
      expect(provider.cached(request), isNotNull);
      expect(provider.cached(MapRequest([18, 53, 19, 54], 10, '04')), isNull);
      expect(
        provider.cached(MapRequest(request.bbox, 10, '04', '24H')),
        isNull,
      );
      await repo.clearData();
      expect(provider.cached(request), isNull);
    },
  );
  test(
    'bad response keeps valid cache and cache is bounded to four viewports',
    () async {
      var bad = false;
      final prefs = await SharedPreferences.getInstance();
      final repo = DataRepository(
        prefs,
        buildApi: 'https://build.example',
        client: MockClient((r) async {
          final q = MapRequest(
            r.url.queryParameters['bbox']!
                .split(',')
                .map(double.parse)
                .toList(),
            double.parse(r.url.queryParameters['zoom']!),
            r.url.queryParameters['regionId']!,
          );
          return bad ? http.Response('not JSON', 200) : response(fixture(q));
        }),
      );
      final provider = ShelterMapProvider(repo);
      for (var zoom = 8; zoom < 14; zoom++) {
        await provider.fetch(MapRequest(request.bbox, zoom.toDouble(), '04'));
      }
      expect(prefs.getKeys().where((k) => k.startsWith('map:')).length, 4);
      final latest = MapRequest(request.bbox, 13, '04');
      bad = true;
      await expectLater(provider.fetch(latest), throwsA(isA<ApiFailure>()));
      expect(provider.cached(latest), isNotNull);
      await repo.setDeveloperApi('https://different.example');
      expect(provider.cached(latest), isNull);
    },
  );
  test('clear data during fetch prevents cache resurrection', () async {
    final pending = Completer<http.Response>();
    final repo = DataRepository(
      await SharedPreferences.getInstance(),
      buildApi: 'https://build.example',
      client: MockClient((_) => pending.future),
    );
    final p = ShelterMapProvider(repo), loading = pending;
    final future = p.fetch(request);
    await repo.clearData();
    loading.complete(response(fixture(request)));
    await expectLater(future, throwsStateError);
    expect(p.cached(request), isNull);
  });
}
