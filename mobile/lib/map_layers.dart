import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'model.dart';
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
