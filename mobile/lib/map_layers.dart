import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'model.dart';
import 'offline_repository.dart';
import 'shelters.dart';

/// Shared layer envelope. A future provider must declare authority; NEPTUN is OSINT.
abstract interface class MapLayerProvider {
  String get layerId;
  Future<MapViewport> fetch(MapRequest request);
}

class MapRequest {
  final List<double> bbox;
  final double zoom;
  final String region, availability;
  MapRequest(this.bbox, this.zoom, this.region, [this.availability = 'ALL']);
  Map<String, String> get query => {
    'bbox': bbox.map((v) => v.toStringAsFixed(6)).join(','),
    'zoom': zoom.toStringAsFixed(1),
    'regionId': region,
    'availability': availability,
  };
  String get key => jsonEncode(query);
}

MapRequest shelterViewportRequest(
  List<double> bbox,
  double zoom, [
  String availability = 'ALL',
]) => MapRequest(bbox, zoom, 'PL', availability);

bool mapDatasetChanged(MapRequest? rendered, MapRequest next) =>
    rendered != null &&
    (rendered.region != next.region ||
        rendered.availability != next.availability);

bool mapEventIsLive(SafetyEvent event, DateTime now) {
  if (!event.hasPoint ||
      event.data['lifecycle'] != 'ACTIVE' ||
      event.data['messageContext'] != 'ACTUAL' ||
      event.data['verification'] == 'REFUTED') {
    return false;
  }
  final validTo = DateTime.tryParse(event.data['validTo']?.toString() ?? '');
  return validTo == null || validTo.isAfter(now);
}

class MapViewport {
  final Map<String, dynamic> data;
  MapViewport._(this.data);
  Map<String, dynamic> get metadata =>
      Map<String, dynamic>.from(data['metadata'] as Map);
  factory MapViewport.parse(String text, MapRequest request) {
    final m = jsonDecode(text) as Map<String, dynamic>;
    final meta = m['metadata'] as Map;
    final features = m['features'] as List;
    if (m['type'] != 'FeatureCollection' ||
        meta['schemaVersion'] != 1 ||
        meta['layerId'] != 'shelters' ||
        meta['authority'] != 'OFFICIAL_PL' ||
        meta['regionId'] != request.region ||
        meta['availability'] != request.availability ||
        features.length > 1089 ||
        meta['returned'] != features.length ||
        meta['total'] is! int ||
        (meta['total'] as int) < 0 ||
        meta['zoom'] != double.parse(request.query['zoom']!)) {
      throw const FormatException('Niepoprawna warstwa mapy');
    }
    final box = (meta['bbox'] as List).cast<num>();
    final requested = request.query['bbox']!
        .split(',')
        .map(double.parse)
        .toList();
    if (box.length != 4 ||
        List.generate(
          4,
          (i) => (box[i] - requested[i]).abs() > 0.000001,
        ).contains(true)) {
      throw const FormatException('Błędny obszar mapy');
    }
    var count = 0;
    for (final f in features) {
      final c = f['geometry']['coordinates'] as List;
      if (f['type'] != 'Feature' ||
          f['geometry']['type'] != 'Point' ||
          c.length != 2 ||
          c.any((v) => v is! num || !v.isFinite) ||
          c[0] < box[0] - 0.000001 ||
          c[0] > box[2] + 0.000001 ||
          c[1] < box[1] - 0.000001 ||
          c[1] > box[3] + 0.000001) {
        throw const FormatException('Niepoprawne współrzędne');
      }
      final p = f['properties'] as Map;
      if (p['cluster'] == true) {
        if (p['point_count'] is! int || p['point_count'] < 1) {
          throw const FormatException('Niepoprawny klaster');
        }
        count += p['point_count'] as int;
      } else {
        final point = ShelterPoint.parse(p);
        if (request.region != 'PL' &&
            point.data['regionId'] != request.region) {
          throw const FormatException('Błędny region punktu');
        }
        if (point.data['longitude'] != c[0] || point.data['latitude'] != c[1]) {
          throw const FormatException('Niespójny punkt');
        }
        count++;
      }
    }
    if (count != meta['total']) {
      throw const FormatException('Niepełna warstwa');
    }
    DateTime.parse(meta['serverTime'] as String);
    return MapViewport._(m);
  }
  bool freshAt(DateTime now) {
    final h = metadata['health'];
    if (h is! Map ||
        h['state'] != 'HEALTHY' ||
        h['complete'] != true ||
        h['maxAgeSeconds'] is! num) {
      return false;
    }
    final success = DateTime.tryParse(h['lastSuccess'] as String? ?? '');
    final source = DateTime.tryParse(h['sourceUpdatedAt'] as String? ?? '');
    return success != null &&
        source != null &&
        !success.isAfter(now.add(const Duration(seconds: 30))) &&
        now.difference(success).inSeconds < h['maxAgeSeconds'] &&
        now.difference(source) < const Duration(days: 14);
  }
}

class ShelterMapProvider implements MapLayerProvider {
  final DataRepository repository;
  ShelterMapProvider(this.repository);
  @override
  String get layerId => 'shelters';
  String cacheKey(MapRequest q) => 'map:${repository.api}:${q.key}';
  MapViewport? cached(MapRequest q) {
    try {
      final raw = repository.prefs.getString(cacheKey(q));
      return raw == null ? null : MapViewport.parse(raw, q);
    } catch (_) {
      return null;
    }
  }

  Future<MapViewport?> offline(MapRequest q) async {
    final package = await repository.offlinePackage(q.region);
    if (package == null) return null;
    final visible = package.shelters
        .where((item) {
          final lon = (item['longitude'] as num).toDouble();
          final lat = (item['latitude'] as num).toDouble();
          return lon >= q.bbox[0] &&
              lon <= q.bbox[2] &&
              lat >= q.bbox[1] &&
              lat <= q.bbox[3] &&
              (q.availability == 'ALL' ||
                  item['availability'] == q.availability);
        })
        .toList(growable: false);

    final features = <Map<String, dynamic>>[];
    if (visible.length <= 500) {
      for (final item in visible) {
        features.add({
          'type': 'Feature',
          'id': item['id'],
          'geometry': {
            'type': 'Point',
            'coordinates': [item['longitude'], item['latitude']],
          },
          'properties': {...item, 'cluster': false},
        });
      }
    } else {
      final width = (q.bbox[2] - q.bbox[0]) / 32;
      final height = (q.bbox[3] - q.bbox[1]) / 32;
      final cells = <String, List<Map<String, dynamic>>>{};
      for (final item in visible) {
        final gx = (((item['longitude'] as num) - q.bbox[0]) / width)
            .floor()
            .clamp(0, 31);
        final gy = (((item['latitude'] as num) - q.bbox[1]) / height)
            .floor()
            .clamp(0, 31);
        cells.putIfAbsent('$gx:$gy', () => []).add(item);
      }
      for (final entry in cells.entries) {
        final rows = entry.value;
        final lon =
            rows.fold<double>(
              0,
              (sum, item) => sum + (item['longitude'] as num).toDouble(),
            ) /
            rows.length;
        final lat =
            rows.fold<double>(
              0,
              (sum, item) => sum + (item['latitude'] as num).toDouble(),
            ) /
            rows.length;
        features.add({
          'type': 'Feature',
          'id': 'offline-cluster-${entry.key}',
          'geometry': {
            'type': 'Point',
            'coordinates': [lon, lat],
          },
          'properties': {
            'cluster': true,
            'point_count': rows.length,
            'expansionZoom': (q.zoom.floor() + 2).clamp(0, 22),
          },
        });
      }
    }
    final source = (package.snapshot['sources'] as List).whereType<Map>().where(
      (item) => item['id'] == 'SHELTERS',
    );
    final originalHealth = source.isEmpty
        ? null
        : Map<String, dynamic>.from(source.first);
    final health = {
      ...?originalHealth,
      'id': 'SHELTERS',
      'state': 'STALE',
      'healthStatus': 'STALE',
      'complete': originalHealth?['complete'] ?? false,
      'maxAgeSeconds': originalHealth?['maxAgeSeconds'] ?? 0,
    };
    return MapViewport._({
      'type': 'FeatureCollection',
      'metadata': {
        'schemaVersion': 1,
        'layerId': 'shelters',
        'authority': 'OFFICIAL_PL',
        ...q.query,
        'bbox': q.bbox,
        'zoom': double.parse(q.query['zoom']!),
        'regionId': q.region,
        'availability': q.availability,
        'total': visible.length,
        'returned': features.length,
        'clustered': visible.length > 500,
        'version': package.shelterVersion,
        'dataDate': visible.isEmpty ? null : visible.first['dataDate'],
        'health': health,
        'serverTime': package.snapshotTimestamp.toIso8601String(),
        'offlinePackageTimestamp': package.snapshotTimestamp.toIso8601String(),
        'basemapIncluded': false,
      },
      'features': features,
    });
  }

  @override
  Future<MapViewport> fetch(MapRequest q) async {
    final key = cacheKey(q), generation = repository.dataGeneration;
    Uri uri;
    try {
      uri = DataRepository.validateApi(repository.api);
    } catch (_) {
      throw const ApiFailure(ApiFailureKind.notConfigured);
    }
    late http.Response response;
    try {
      response = await repository.client
          .get(
            uri.replace(
              path: '${uri.path}/v1/map/shelters',
              queryParameters: q.query,
            ),
            headers: {'Accept': 'application/geo+json,application/json'},
          )
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const ApiFailure(ApiFailureKind.timeout);
    } on http.ClientException {
      throw const ApiFailure(ApiFailureKind.network);
    } catch (error) {
      if (error is ApiFailure) rethrow;
      throw const ApiFailure(ApiFailureKind.network);
    }
    if (response.statusCode == 429) {
      throw const ApiFailure(ApiFailureKind.rateLimited, 429);
    }
    if (response.statusCode >= 500) {
      throw ApiFailure(ApiFailureKind.server, response.statusCode);
    }
    if (response.statusCode != 200 ||
        response.bodyBytes.length > 2 * 1024 * 1024) {
      throw ApiFailure(ApiFailureKind.invalidResponse, response.statusCode);
    }
    final raw = utf8.decode(response.bodyBytes);
    late MapViewport viewport;
    try {
      viewport = MapViewport.parse(raw, q);
    } catch (_) {
      throw const ApiFailure(ApiFailureKind.invalidResponse);
    }
    if (generation != repository.dataGeneration || key != cacheKey(q)) {
      throw StateError('Konfiguracja zmieniona');
    }
    // Four bounded viewports across all regions/servers; never the entire national catalog.
    final keys =
        repository.prefs
            .getKeys()
            .where((k) => k.startsWith('map:') && k != key)
            .toList()
          ..sort((a, b) {
            try {
              return (jsonDecode(
                        repository.prefs.getString(a)!,
                      )['metadata']['serverTime']
                      as String)
                  .compareTo(
                    jsonDecode(
                          repository.prefs.getString(b)!,
                        )['metadata']['serverTime']
                        as String,
                  );
            } catch (_) {
              return 0;
            }
          });
    while (keys.length >= 4) {
      await repository.prefs.remove(keys.removeAt(0));
    }
    await repository.prefs.setString(key, raw);
    return viewport;
  }
}
