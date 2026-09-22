import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'model.dart';
import 'offline_packages.dart';
import 'shelters.dart';

extension OfflineRepository on DataRepository {
  OfflinePackageStore get offlinePackages => OfflinePackageStore(prefs);

  Future<List<OfflinePackageDescriptor>> listOfflinePackages() =>
      offlinePackages.list();

  Future<int> offlineUsedBytes() => offlinePackages.usedBytes();

  Future<void> deleteOfflinePackage(String regionId) =>
      offlinePackages.delete(regionId);

  Future<OfflineRegionPackage?> offlinePackage(String regionId) async {
    try {
      return await offlinePackages.load(regionId);
    } catch (_) {
      return null;
    }
  }

  Future<Snapshot?> offlineSnapshot(String regionId) async {
    final package = await offlinePackage(regionId);
    if (package == null) return null;
    try {
      final snapshot = Snapshot.parse(jsonEncode(package.snapshot));
      return snapshot.region == regionId ? snapshot : null;
    } catch (_) {
      return null;
    }
  }

  Future<OfflineRegionPackage> downloadOfflinePackage(String regionId) async {
    if (!regions.containsKey(regionId)) {
      throw const OfflinePackageException('INVALID_REGION');
    }
    final base = _offlineApi(this);
    final snapshotResponse = await _offlineGet(
      this,
      base.replace(
        path: '${base.path}/v1/snapshot',
        queryParameters: {'regionId': regionId},
      ),
      4 * 1024 * 1024,
    );
    Snapshot snapshot;
    try {
      snapshot = Snapshot.parse(utf8.decode(snapshotResponse.bodyBytes));
    } catch (_) {
      throw const ApiFailure(ApiFailureKind.invalidResponse);
    }
    if (snapshot.region != regionId) {
      throw const ApiFailure(ApiFailureKind.invalidResponse);
    }

    String? backendVersion;
    try {
      final health = await _offlineGet(
        this,
        base.replace(path: '${base.path}/healthz'),
        128 * 1024,
      );
      final decoded = jsonDecode(utf8.decode(health.bodyBytes));
      if (decoded is Map && decoded['version'] is String) {
        backendVersion = decoded['version'] as String;
      }
    } catch (_) {
      backendVersion = null;
    }

    final shelters = <Map<String, dynamic>>[];
    String? version;
    int offset = 0;
    int? expectedTotal;
    Map<String, dynamic>? shelterHealth;
    while (true) {
      final query = <String, String>{
        'regionId': regionId,
        'q': '',
        'offset': '$offset',
        'limit': '500',
        ?'version': version,
      };
      final response = await _offlineGet(
        this,
        base.replace(path: '${base.path}/v1/shelters', queryParameters: query),
        4 * 1024 * 1024,
      );
      ShelterPage page;
      try {
        page = ShelterPage.parse(jsonDecode(utf8.decode(response.bodyBytes)));
      } catch (_) {
        throw const ApiFailure(ApiFailureKind.invalidResponse);
      }
      if (page.region != regionId ||
          page.query.isNotEmpty ||
          page.offset != offset ||
          (version != null && page.version != version)) {
        throw const ApiFailure(ApiFailureKind.invalidResponse);
      }
      expectedTotal ??= page.total;
      if (page.total != expectedTotal ||
          page.total > OfflineRegionPackage.maxShelters) {
        throw const OfflinePackageException('SHELTER_COUNT_BOUNDS');
      }
      version ??= page.version;
      shelterHealth ??= page.health;
      shelters.addAll(page.items.map((point) => point.data));
      if (!page.hasMore) break;
      offset += page.items.length;
      if (page.items.isEmpty || offset > page.total) {
        throw const ApiFailure(ApiFailureKind.invalidResponse);
      }
    }
    if (shelters.length != expectedTotal ||
        shelters.map((item) => item['id']).toSet().length != shelters.length) {
      throw const ApiFailure(ApiFailureKind.invalidResponse);
    }

    final sourceTimestamps = <String, dynamic>{};
    for (final raw in snapshot.data['sources'] as List) {
      if (raw is! Map || raw['id'] is! String) continue;
      sourceTimestamps[raw['id'] as String] = {
        'state': raw['healthStatus'] ?? raw['state'],
        'lastSuccess': raw['lastSuccess'],
        'lastItemTime': raw['lastItemTime'],
        'sourceUpdatedAt': raw['sourceUpdatedAt'],
      };
    }
    if (shelterHealth != null) {
      sourceTimestamps['SHELTERS'] = {
        'state': shelterHealth['healthStatus'] ?? shelterHealth['state'],
        'lastSuccess': shelterHealth['lastSuccess'],
        'sourceUpdatedAt': shelterHealth['sourceUpdatedAt'],
        'dataDate': shelterHealth['dataDate'],
      };
    }

    final layers = <String>['shelters-local'];
    if (snapshot.events.any(
      (event) => event.hasPoint || event.data['geometry'] != null,
    )) {
      layers.add('events-local');
    }
    if (snapshot.data['radiation'] is Map) {
      layers.add('radiation-local');
    }
    final package = OfflineRegionPackage.create(
      regionId: regionId,
      createdAt: DateTime.now().toUtc(),
      snapshotTimestamp: DateTime.parse(
        snapshot.data['serverTime'] as String,
      ).toUtc(),
      snapshot: snapshot.data,
      shelters: shelters,
      watchedLocations: watchedLocations.map((item) => item.toJson()).toList(),
      sourceTimestamps: sourceTimestamps,
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
      layers: layers,
      shelterVersion: version,
      backendVersion: backendVersion,
    );
    await offlinePackages.commit(package);

    // Keep the existing lightweight caches useful without making them the
    // authority for package integrity.
    await prefs.setString(cacheKey(regionId), jsonEncode(snapshot.data));
    final firstPage = await offlineShelterPage(regionId, limit: 50);
    if (firstPage != null) {
      await prefs.setString(
        shelterCacheKey(regionId),
        jsonEncode(firstPage.data),
      );
    }
    return package;
  }

  Future<ShelterPage?> offlineShelterPage(
    String regionId, {
    String query = '',
    int offset = 0,
    int limit = 50,
  }) async {
    final package = await offlinePackage(regionId);
    if (package == null) return null;
    final normalized = query.trim().toLowerCase();
    final matches = package.shelters.where((item) {
      if (normalized.isEmpty) return true;
      final text = [
        item['address'],
        item['municipality'],
        item['county'],
      ].whereType<String>().join(' ').toLowerCase();
      return text.contains(normalized);
    }).toList(growable: false);
    if (offset < 0 || offset > matches.length || limit < 1 || limit > 500) {
      throw const ApiFailure(ApiFailureKind.invalidResponse);
    }
    final end = math.min(offset + limit, matches.length).toInt();
    final source = (package.snapshot['sources'] as List)
        .whereType<Map>()
        .where((item) => item['id'] == 'SHELTERS');
    final originalHealth = source.isEmpty
        ? null
        : Map<String, dynamic>.from(source.first);
    final health = <String, dynamic>{
      'id': 'SHELTERS',
      'name': originalHealth?['name'] ?? 'Punkty schronienia PSP',
      'url': originalHealth?['url'] ??
          'https://dane.gov.pl/pl/dataset/28058,punkty-schronienia-w-polsce',
      'state': 'STALE',
      'healthStatus': 'STALE',
      'maxAgeSeconds': originalHealth?['maxAgeSeconds'] ?? 0,
      'complete': originalHealth?['complete'] ?? false,
      'lastSuccess': originalHealth?['lastSuccess'],
      'sourceUpdatedAt': originalHealth?['sourceUpdatedAt'],
      'dataDate': originalHealth?['dataDate'],
      'offlineSnapshotTimestamp': package.snapshotTimestamp.toIso8601String(),
    };
    return ShelterPage.parse({
      'schemaVersion': 1,
      'serverTime': package.snapshotTimestamp.toIso8601String(),
      'regionId': regionId,
      'query': query.trim(),
      'items': matches.sublist(offset, end),
      'total': matches.length,
      'offset': offset,
      'limit': limit,
      'hasMore': end < matches.length,
      'version': package.shelterVersion,
      'health': health,
    });
  }

  Future<NearestSheltersResult?> offlineNearestShelters(
    double latitude,
    double longitude, {
    int limit = 3,
    String? regionId,
  }) async {
    final selectedRegion = regionId ?? region;
    final package = await offlinePackage(selectedRegion);
    if (package == null) return null;
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180 ||
        limit < 1 ||
        limit > 10) {
      throw const ApiFailure(ApiFailureKind.invalidResponse);
    }
    final rows = package.shelters.map((item) {
      final distance = _distanceMeters(
        latitude,
        longitude,
        (item['latitude'] as num).toDouble(),
        (item['longitude'] as num).toDouble(),
      );
      return {'point': item, 'distanceMeters': distance};
    }).toList()
      ..sort(
        (a, b) => (a['distanceMeters'] as int).compareTo(
          b['distanceMeters'] as int,
        ),
      );
    final health = {
      'id': 'SHELTERS',
      'state': 'STALE',
      'healthStatus': 'STALE',
      'maxAgeSeconds': 0,
      'offlineSnapshotTimestamp': package.snapshotTimestamp.toIso8601String(),
    };
    return NearestSheltersResult.parse({
      'schemaVersion': 1,
      'serverTime': package.snapshotTimestamp.toIso8601String(),
      'items': rows.take(limit).toList(),
      'health': health,
    });
  }

  Future<AroundResult?> offlineAround(
    double latitude,
    double longitude, {
    double radiusKm = 20,
    String? regionId,
  }) async {
    final selectedRegion = regionId ?? region;
    final package = await offlinePackage(selectedRegion);
    if (package == null) return null;
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        !radiusKm.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180 ||
        radiusKm < 1 ||
        radiusKm > 100) {
      throw const ApiFailure(ApiFailureKind.invalidResponse);
    }
    final nearby = <Map<String, dynamic>>[];
    final regional = <Map<String, dynamic>>[];
    for (final raw in package.snapshot['events'] as List) {
      if (raw is! Map) continue;
      final event = Map<String, dynamic>.from(raw);
      final lat = event['latitude'], lon = event['longitude'];
      if (lat is num && lon is num) {
        final distance = _distanceMeters(
          latitude,
          longitude,
          lat.toDouble(),
          lon.toDouble(),
        );
        if (distance <= radiusKm * 1000) {
          nearby.add({
            'event': event,
            'distanceMeters': distance,
            'relevance': 'NEARBY',
          });
        }
      } else if (regionId != null &&
          event['regions'] is List &&
          ((event['regions'] as List).contains(regionId) ||
              (event['regions'] as List).contains('PL'))) {
        regional.add({'event': event, 'relevance': 'REGION_RELEVANT'});
      }
    }
    nearby.sort(
      (a, b) => (a['distanceMeters'] as int).compareTo(
        b['distanceMeters'] as int,
      ),
    );
    final nearest = await offlineNearestShelters(
      latitude,
      longitude,
      limit: 3,
      regionId: selectedRegion,
    );
    return AroundResult.parse({
      'schemaVersion': 1,
      'serverTime': package.snapshotTimestamp.toIso8601String(),
      'query': {
        'latitude': latitude,
        'longitude': longitude,
        'radiusKm': radiusKm,
        'regionId': regionId,
      },
      'nearbyEvents': nearby.take(50).toList(),
      'regionalEvents': regional.take(50).toList(),
      'nearestShelters': {
        'items': nearest?.items
                .map(
                  (item) => {
                    'point': item.point.data,
                    'distanceMeters': item.distanceMeters,
                  },
                )
                .toList() ??
            const [],
        'health': nearest?.health,
      },
      'coverage': {
        'spatial': 'PARTIAL_GEOMETRY_ONLY',
        'regional': regionId == null
            ? 'NOT_REQUESTED'
            : 'EXPLICIT_NATIONAL_OR_PROVINCE_SCOPE_ONLY',
        'statement':
            'OFFLINE / LAST KNOWN GOOD z ${package.snapshotTimestamp.toIso8601String()}. Brak nowych danych nie oznacza bezpieczeństwa.',
      },
      'offlineSnapshotTimestamp': package.snapshotTimestamp.toIso8601String(),
    });
  }
}

Uri _offlineApi(DataRepository repository) {
  if (repository.api.isEmpty) {
    throw const ApiFailure(ApiFailureKind.notConfigured);
  }
  try {
    return DataRepository.validateApi(repository.api);
  } catch (_) {
    throw const ApiFailure(ApiFailureKind.notConfigured);
  }
}

Future<http.Response> _offlineGet(
  DataRepository repository,
  Uri uri,
  int maxBytes,
) async {
  late http.Response response;
  try {
    response = await repository.client
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 20));
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
  if (response.statusCode != 200 || response.bodyBytes.length > maxBytes) {
    throw ApiFailure(ApiFailureKind.invalidResponse, response.statusCode);
  }
  return response;
}

int _distanceMeters(double lat1, double lon1, double lat2, double lon2) {
  const radius = 6371000.0;
  final p1 = lat1 * math.pi / 180;
  final p2 = lat2 * math.pi / 180;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLon = (lon2 - lon1) * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(p1) *
          math.cos(p2) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return (radius * c).round();
}