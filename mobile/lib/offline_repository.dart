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
        'version': ?version,
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