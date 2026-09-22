import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'shelters.dart';

enum OfflinePackageState {
  current,
  stale,
  corrupted,
  incomplete,
  refreshRequired,
}

String offlinePackageStateLabel(OfflinePackageState state) => switch (state) {
  OfflinePackageState.current => 'AKTUALNY SNAPSHOT',
  OfflinePackageState.stale => 'STARY / LAST KNOWN GOOD',
  OfflinePackageState.corrupted => 'USZKODZONY',
  OfflinePackageState.incomplete => 'NIEKOMPLETNY',
  OfflinePackageState.refreshRequired => 'WYMAGA ODŚWIEŻENIA',
};

class OfflinePackageException implements Exception {
  final String code;
  const OfflinePackageException(this.code);
  @override
  String toString() => 'OfflinePackageException($code)';
}

class OfflineRegionPackage {
  static const schemaVersion = 1;
  static const maxSingleBytes = 12 * 1024 * 1024;
  static const maxShelters = 50000;
  static const appVersion = '0.1.0-alpha.15';

  final Map<String, dynamic> data;
  final int encodedBytes;

  OfflineRegionPackage._(this.data, this.encodedBytes);

  Map<String, dynamic> get manifest =>
      Map<String, dynamic>.from(data['manifest'] as Map);
  Map<String, dynamic> get payload =>
      Map<String, dynamic>.from(data['payload'] as Map);
  String get regionId => manifest['regionId'] as String;
  DateTime get createdAt => DateTime.parse(manifest['createdAt'] as String);
  DateTime get snapshotTimestamp =>
      DateTime.parse(manifest['snapshotTimestamp'] as String);
  String? get shelterVersion => manifest['shelterVersion'] as String?;
  List<String> get components =>
      List<String>.from(manifest['components'] as List);
  List<String> get layers => List<String>.from(manifest['layers'] as List);
  Map<String, dynamic> get snapshot =>
      Map<String, dynamic>.from(payload['snapshot'] as Map);
  List<Map<String, dynamic>> get shelters => (payload['shelters'] as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList(growable: false);
  List<Map<String, dynamic>> get watchedLocations =>
      (payload['watchedLocations'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);

  OfflinePackageState stateAt(DateTime now) {
    final validUntil = DateTime.tryParse(
      (snapshot['status'] as Map?)?['validUntil'] as String? ?? '',
    );
    if (createdAt.isAfter(now.add(const Duration(minutes: 5)))) {
      return OfflinePackageState.stale;
    }
    if (now.difference(createdAt) > const Duration(minutes: 30) ||
        validUntil == null ||
        !now.isBefore(validUntil)) {
      return OfflinePackageState.stale;
    }
    return OfflinePackageState.current;
  }

  String encode() => jsonEncode(data);

  static OfflineRegionPackage create({
    required String regionId,
    required DateTime createdAt,
    required DateTime snapshotTimestamp,
    required Map<String, dynamic> snapshot,
    required List<Map<String, dynamic>> shelters,
    required List<Map<String, dynamic>> watchedLocations,
    required Map<String, dynamic> sourceTimestamps,
    required List<String> components,
    required List<String> layers,
    String? shelterVersion,
    String? backendVersion,
  }) {
    final payload = <String, dynamic>{
      'snapshot': snapshot,
      'shelters': shelters,
      'watchedLocations': watchedLocations,
      'map': {
        'basemapIncluded': false,
        'basemapStatus': 'ONLINE_ONLY_OR_PROVIDER_CACHE',
        'layers': layers,
      },
    };
    final payloadText = jsonEncode(payload);
    final manifest = <String, dynamic>{
      'regionId': regionId,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'dataTimestamp': snapshotTimestamp.toUtc().toIso8601String(),
      'snapshotTimestamp': snapshotTimestamp.toUtc().toIso8601String(),
      'schemaVersion': schemaVersion,
      'appVersion': appVersion,
      'backendVersion': backendVersion,
      'sourceTimestamps': sourceTimestamps,
      'sizeBytes': utf8.encode(payloadText).length,
      'components': components,
      'checksum': {
        'algorithm': 'CRC32',
        'value': _crc32Hex(utf8.encode(payloadText)),
      },
      'shelterVersion': shelterVersion,
      'layers': layers,
    };
    return parse(
      jsonEncode({
        'schemaVersion': schemaVersion,
        'manifest': manifest,
        'payload': payload,
      }),
    );
  }

  static OfflineRegionPackage parse(String raw) {
    final encoded = utf8.encode(raw);
    if (encoded.isEmpty || encoded.length > maxSingleBytes) {
      throw const OfflinePackageException('SIZE_BOUNDS');
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      throw const OfflinePackageException('INVALID_JSON');
    }
    if (decoded is! Map) {
      throw const OfflinePackageException('INVALID_STRUCTURE');
    }
    final map = Map<String, dynamic>.from(decoded);
    if (map['schemaVersion'] is! int) {
      throw const OfflinePackageException('MISSING_SCHEMA_VERSION');
    }
    if (map['schemaVersion'] != schemaVersion) {
      throw const OfflinePackageException('UNSUPPORTED_SCHEMA_VERSION');
    }
    if (map['manifest'] is! Map || map['payload'] is! Map) {
      throw const OfflinePackageException('INCOMPLETE');
    }
    final manifest = Map<String, dynamic>.from(map['manifest'] as Map);
    final payload = Map<String, dynamic>.from(map['payload'] as Map);
    if (manifest['schemaVersion'] != schemaVersion ||
        manifest['regionId'] is! String ||
        manifest['createdAt'] is! String ||
        manifest['dataTimestamp'] is! String ||
        manifest['snapshotTimestamp'] is! String ||
        manifest['appVersion'] is! String ||
        manifest['sourceTimestamps'] is! Map ||
        manifest['sizeBytes'] is! int ||
        manifest['components'] is! List ||
        manifest['checksum'] is! Map ||
        manifest['layers'] is! List ||
        payload['snapshot'] is! Map ||
        payload['shelters'] is! List ||
        payload['watchedLocations'] is! List ||
        payload['map'] is! Map) {
      throw const OfflinePackageException('INCOMPLETE');
    }
    final region = manifest['regionId'] as String;
    if (region != 'PL' &&
        !RegExp(r'^(02|04|06|08|10|12|14|16|18|20|22|24|26|28|30|32)$')
            .hasMatch(region)) {
      throw const OfflinePackageException('INVALID_REGION');
    }
    try {
      DateTime.parse(manifest['createdAt'] as String);
      DateTime.parse(manifest['dataTimestamp'] as String);
      DateTime.parse(manifest['snapshotTimestamp'] as String);
    } catch (_) {
      throw const OfflinePackageException('INVALID_TIMESTAMP');
    }
    final snapshot = Map<String, dynamic>.from(payload['snapshot'] as Map);
    if (snapshot['schemaVersion'] != 1 ||
        snapshot['regionId'] != region ||
        snapshot['serverTime'] is! String ||
        snapshot['status'] is! Map ||
        snapshot['nationalStatus'] is! Map ||
        snapshot['events'] is! List ||
        snapshot['sources'] is! List ||
        snapshot['incidents'] is! List) {
      throw const OfflinePackageException('INVALID_SNAPSHOT');
    }
    try {
      DateTime.parse(snapshot['serverTime'] as String);
    } catch (_) {
      throw const OfflinePackageException('INVALID_SNAPSHOT_TIMESTAMP');
    }
    if (snapshot['ukraineAlerts'] is List &&
        (snapshot['ukraineAlerts'] as List).isNotEmpty) {
      throw const OfflinePackageException('UA_ISOLATION');
    }
    if ((snapshot['events'] as List).any((dynamic rawEvent) {
      if (rawEvent is! Map) return true;
      final e = Map<String, dynamic>.from(rawEvent);
      final sources = e['sources'];
      return e['countryCode'] == 'UA' ||
          e['ukraine'] != null ||
          (sources is List &&
              sources.any((dynamic s) => s is Map && s['id'] == 'UA'));
    })) {
      throw const OfflinePackageException('UA_ISOLATION');
    }
    if (payload.containsKey('neptun')) {
      throw const OfflinePackageException('NEPTUN_ISOLATION');
    }

    final shelterRows = payload['shelters'] as List;
    if (shelterRows.length > maxShelters) {
      throw const OfflinePackageException('SHELTER_COUNT_BOUNDS');
    }
    final shelterIds = <String>{};
    for (final item in shelterRows) {
      ShelterPoint point;
      try {
        point = ShelterPoint.parse(item);
      } catch (_) {
        throw const OfflinePackageException('INVALID_SHELTER');
      }
      if (region != 'PL' && point.data['regionId'] != region) {
        throw const OfflinePackageException('SHELTER_REGION_MISMATCH');
      }
      if (!shelterIds.add(point.id)) {
        throw const OfflinePackageException('DUPLICATE_SHELTER');
      }
    }
    for (final rawLocation in payload['watchedLocations'] as List) {
      if (rawLocation is! Map) {
        throw const OfflinePackageException('INVALID_WATCHED_LOCATION');
      }
      final location = Map<String, dynamic>.from(rawLocation);
      final lat = location['latitude'], lon = location['longitude'];
      if (location['id'] is! String ||
          location['label'] is! String ||
          lat is! num ||
          lon is! num ||
          !lat.isFinite ||
          !lon.isFinite ||
          lat.abs() > 90 ||
          lon.abs() > 180) {
        throw const OfflinePackageException('INVALID_WATCHED_LOCATION');
      }
    }
    final mapMeta = Map<String, dynamic>.from(payload['map'] as Map);
    if (mapMeta['basemapIncluded'] != false || mapMeta['layers'] is! List) {
      throw const OfflinePackageException('INVALID_MAP_METADATA');
    }
    final payloadText = jsonEncode(payload);
    final payloadBytes = utf8.encode(payloadText);
    if (manifest['sizeBytes'] != payloadBytes.length) {
      throw const OfflinePackageException('SIZE_MISMATCH');
    }
    final checksum = Map<String, dynamic>.from(manifest['checksum'] as Map);
    if (checksum['algorithm'] != 'CRC32' ||
        checksum['value'] is! String ||
        checksum['value'] != _crc32Hex(payloadBytes)) {
      throw const OfflinePackageException('CHECKSUM_MISMATCH');
    }
    return OfflineRegionPackage._(map, encoded.length);
  }
}

class OfflinePackageDescriptor {
  final String regionId;
  final OfflinePackageState state;
  final int sizeBytes;
  final DateTime? createdAt;
  final DateTime? snapshotTimestamp;
  final OfflineRegionPackage? package;
  final String? errorCode;

  const OfflinePackageDescriptor({
    required this.regionId,
    required this.state,
    required this.sizeBytes,
    this.createdAt,
    this.snapshotTimestamp,
    this.package,
    this.errorCode,
  });
}

class OfflinePackageStore {
  static const maxPackages = 6;
  static const maxTotalBytes = 32 * 1024 * 1024;
  static const _activePrefix = 'offline_package_active_v1:';
  static const _dataPrefix = 'offline_package_data_v1:';
  static const _backupPrefix = 'offline_package_backup_v1:';
  static const _stagingPrefix = 'offline_package_staging_v1:';
  static const _accessPrefix = 'offline_package_access_v1:';

  final SharedPreferences prefs;
  OfflinePackageStore(this.prefs);

  String _active(String region) => '$_activePrefix$region';
  String _backup(String region) => '$_backupPrefix$region';
  String _staging(String region) => '$_stagingPrefix$region';
  String _access(String region) => '$_accessPrefix$region';
  String _data(String region, DateTime createdAt) =>
      '$_dataPrefix$region:${createdAt.microsecondsSinceEpoch}';

  Future<List<OfflinePackageDescriptor>> list() async {
    final result = <OfflinePackageDescriptor>[];
    final keys = prefs
        .getKeys()
        .where((key) => key.startsWith(_activePrefix))
        .toList();
    for (final key in keys) {
      final region = key.substring(_activePrefix.length);
      final pointer = prefs.getString(key);
      if (pointer == null || pointer.isEmpty) {
        result.add(
          OfflinePackageDescriptor(
            regionId: region,
            state: OfflinePackageState.incomplete,
            sizeBytes: 0,
            errorCode: 'MISSING_ACTIVE_POINTER',
          ),
        );
        continue;
      }
      final raw = prefs.getString(pointer);
      if (raw == null) {
        result.add(
          OfflinePackageDescriptor(
            regionId: region,
            state: OfflinePackageState.incomplete,
            sizeBytes: 0,
            errorCode: 'MISSING_PACKAGE_DATA',
          ),
        );
        continue;
      }
      try {
        final package = OfflineRegionPackage.parse(raw);
        if (package.regionId != region) {
          throw const OfflinePackageException('ACTIVE_REGION_MISMATCH');
        }
        result.add(
          OfflinePackageDescriptor(
            regionId: region,
            state: package.stateAt(DateTime.now().toUtc()),
            sizeBytes: package.encodedBytes,
            createdAt: package.createdAt,
            snapshotTimestamp: package.snapshotTimestamp,
            package: package,
          ),
        );
      } on OfflinePackageException catch (error) {
        result.add(
          OfflinePackageDescriptor(
            regionId: region,
            state: error.code == 'UNSUPPORTED_SCHEMA_VERSION'
                ? OfflinePackageState.refreshRequired
                : error.code == 'INCOMPLETE'
                ? OfflinePackageState.incomplete
                : OfflinePackageState.corrupted,
            sizeBytes: utf8.encode(raw).length,
            errorCode: error.code,
          ),
        );
      } catch (_) {
        result.add(
          OfflinePackageDescriptor(
            regionId: region,
            state: OfflinePackageState.corrupted,
            sizeBytes: utf8.encode(raw).length,
            errorCode: 'READ_FAILED',
          ),
        );
      }
    }
    result.sort((a, b) {
      final aa = prefs.getInt(_access(a.regionId)) ?? 0;
      final bb = prefs.getInt(_access(b.regionId)) ?? 0;
      return bb.compareTo(aa);
    });
    return result;
  }

  Future<OfflineRegionPackage?> load(String region) async {
    final activePointer = prefs.getString(_active(region));
    OfflinePackageException? activeError;
    if (activePointer != null) {
      final raw = prefs.getString(activePointer);
      if (raw != null) {
        try {
          final package = OfflineRegionPackage.parse(raw);
          if (package.regionId != region) {
            throw const OfflinePackageException('ACTIVE_REGION_MISMATCH');
          }
          await prefs.setInt(
            _access(region),
            DateTime.now().toUtc().millisecondsSinceEpoch,
          );
          return package;
        } on OfflinePackageException catch (error) {
          activeError = error;
        }
      } else {
        activeError = const OfflinePackageException('MISSING_PACKAGE_DATA');
      }
    }

    final backupPointer = prefs.getString(_backup(region));
    if (backupPointer != null) {
      final raw = prefs.getString(backupPointer);
      if (raw != null) {
        final package = OfflineRegionPackage.parse(raw);
        if (package.regionId != region) {
          throw const OfflinePackageException('BACKUP_REGION_MISMATCH');
        }
        await prefs.setInt(
          _access(region),
          DateTime.now().toUtc().millisecondsSinceEpoch,
        );
        return package;
      }
    }
    if (activeError != null) throw activeError;
    return null;
  }

  Future<void> commit(OfflineRegionPackage package) async {
    final encoded = package.encode();
    final validated = OfflineRegionPackage.parse(encoded);
    if (validated.encodedBytes > OfflineRegionPackage.maxSingleBytes) {
      throw const OfflinePackageException('PACKAGE_TOO_LARGE');
    }
    final before = await list();
    final currentOther = before
        .where((item) => item.regionId != package.regionId)
        .toList();
    final otherBytes = currentOther.fold<int>(
      0,
      (sum, item) => sum + item.sizeBytes,
    );
    if (currentOther.length == 1 &&
        otherBytes + validated.encodedBytes > maxTotalBytes) {
      throw const OfflinePackageException('STORAGE_LIMIT_PRESERVE_LKG');
    }

    final stagingKey = _staging(package.regionId);
    final candidateKey = _data(package.regionId, package.createdAt);
    final previousKey = prefs.getString(_active(package.regionId));
    final oldBackupKey = prefs.getString(_backup(package.regionId));
    if (!await prefs.setString(stagingKey, encoded)) {
      throw const OfflinePackageException('STAGING_WRITE_FAILED');
    }
    final staged = prefs.getString(stagingKey);
    if (staged == null) {
      throw const OfflinePackageException('STAGING_MISSING');
    }
    OfflineRegionPackage.parse(staged);
    if (!await prefs.setString(candidateKey, staged)) {
      throw const OfflinePackageException('COMMIT_WRITE_FAILED');
    }
    OfflineRegionPackage.parse(prefs.getString(candidateKey)!);

    String? newBackupKey = oldBackupKey;
    if (previousKey != null && previousKey != candidateKey) {
      final previousRaw = prefs.getString(previousKey);
      if (previousRaw != null) {
        try {
          final previousPackage = OfflineRegionPackage.parse(previousRaw);
          if (previousPackage.regionId == package.regionId) {
            newBackupKey = previousKey;
            if (!await prefs.setString(
              _backup(package.regionId),
              previousKey,
            )) {
              throw const OfflinePackageException('BACKUP_POINTER_FAILED');
            }
          }
        } on OfflinePackageException {
          // Never promote a broken active package over an existing valid backup.
        }
      }
    }

    if (!await prefs.setString(_active(package.regionId), candidateKey)) {
      throw const OfflinePackageException('ACTIVATION_FAILED');
    }
    await prefs.setInt(
      _access(package.regionId),
      DateTime.now().toUtc().millisecondsSinceEpoch,
    );
    await prefs.remove(stagingKey);
    if (oldBackupKey != null &&
        oldBackupKey != newBackupKey &&
        oldBackupKey != candidateKey) {
      await prefs.remove(oldBackupKey);
    }
    await _enforceLimits(protectedRegion: package.regionId);
  }

  int _storedBytes() {
    final keys = prefs
        .getKeys()
        .where((key) => key.startsWith(_dataPrefix))
        .toSet();
    return keys.fold<int>(
      0,
      (sum, key) => sum + utf8.encode(prefs.getString(key) ?? '').length,
    );
  }

  Future<void> _enforceLimits({required String protectedRegion}) async {
    var packages = await list();
    while ((packages.length > maxPackages || _storedBytes() > maxTotalBytes) &&
        packages.length > 1) {
      final candidates =
          packages.where((item) => item.regionId != protectedRegion).toList()
            ..sort((a, b) {
              final aa = prefs.getInt(_access(a.regionId)) ?? 0;
              final bb = prefs.getInt(_access(b.regionId)) ?? 0;
              return aa.compareTo(bb);
            });
      if (candidates.isEmpty) break;
      await delete(candidates.first.regionId);
      packages = await list();
    }

    if (_storedBytes() > maxTotalBytes) {
      final backupKey = prefs.getString(_backup(protectedRegion));
      if (backupKey != null) {
        await prefs.remove(backupKey);
        await prefs.remove(_backup(protectedRegion));
      }
    }
    if (packages.length > maxPackages || _storedBytes() > maxTotalBytes) {
      throw const OfflinePackageException('STORAGE_LIMIT');
    }
  }

  Future<void> delete(String region) async {
    final pointer = prefs.getString(_active(region));
    if (pointer != null) await prefs.remove(pointer);
    await prefs.remove(_active(region));
    await prefs.remove(_backup(region));
    await prefs.remove(_staging(region));
    await prefs.remove(_access(region));
    for (final key
        in prefs
            .getKeys()
            .where((key) => key.startsWith('$_dataPrefix$region:'))
            .toList()) {
      await prefs.remove(key);
    }
  }

  Future<int> usedBytes() async => _storedBytes();

  Future<void> discardStaging() async {
    for (final key
        in prefs
            .getKeys()
            .where((key) => key.startsWith(_stagingPrefix))
            .toList()) {
      await prefs.remove(key);
    }
  }
}

String formatOfflineBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String formatOfflineAge(DateTime? timestamp, DateTime now) {
  if (timestamp == null) return 'wiek nieznany';
  final age = now.toUtc().difference(timestamp.toUtc());
  if (age.isNegative) return 'czas z przyszłości — traktuj jako STALE';
  if (age.inMinutes < 1) return 'mniej niż minutę';
  if (age.inHours < 1) return '${age.inMinutes} min';
  if (age.inDays < 1) return '${age.inHours} h';
  return '${age.inDays} d';
}

String _crc32Hex(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return ((crc ^ 0xffffffff) & 0xffffffff).toRadixString(16).padLeft(8, '0');
}
