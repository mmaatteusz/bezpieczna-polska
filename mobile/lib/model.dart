import 'radiation.dart';
import 'dart:async';
import 'dart:convert';

import 'shelters.dart';
import 'security_levels.dart';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

enum ApiFailureKind {
  notConfigured,
  timeout,
  network,
  server,
  rateLimited,
  invalidResponse,
}

class ApiFailure implements Exception {
  final ApiFailureKind kind;
  final int? statusCode;
  const ApiFailure(this.kind, [this.statusCode]);
}

String apiFailureMessage(Object error) {
  if (error is ApiFailure) {
    return switch (error.kind) {
      ApiFailureKind.notConfigured =>
        'Aplikacja nie ma skonfigurowanego połączenia z backendem.',
      ApiFailureKind.timeout =>
        'Serwer nie odpowiedział na czas. Zachowano ostatnią poprawną kopię danych.',
      ApiFailureKind.network =>
        'Brak połączenia z serwerem. Sprawdź internet; zapisane dane pozostają dostępne.',
      ApiFailureKind.rateLimited =>
        'Serwer chwilowo ogranicza liczbę zapytań. Spróbuj ponownie za moment.',
      ApiFailureKind.server =>
        'Usługa jest chwilowo niedostępna. Zachowano ostatnią poprawną kopię danych.',
      ApiFailureKind.invalidResponse =>
        'Serwer zwrócił niepoprawne dane. Nie zastąpiono ostatniej poprawnej kopii.',
    };
  }
  if (error is ShelterVersionChanged) {
    return 'Zbiór schronień został zaktualizowany. Odświeżono listę od początku.';
  }
  return 'Nie udało się pobrać danych. Zachowano ostatnią poprawną kopię.';
}

const regions = <String, String>{
  'PL': 'Cała Polska',
  '02': 'Dolnośląskie',
  '04': 'Kujawsko-pomorskie',
  '06': 'Lubelskie',
  '08': 'Lubuskie',
  '10': 'Łódzkie',
  '12': 'Małopolskie',
  '14': 'Mazowieckie',
  '16': 'Opolskie',
  '18': 'Podkarpackie',
  '20': 'Podlaskie',
  '22': 'Pomorskie',
  '24': 'Śląskie',
  '26': 'Świętokrzyskie',
  '28': 'Warmińsko-mazurskie',
  '30': 'Wielkopolskie',
  '32': 'Zachodniopomorskie',
};

class SafetyEvent {
  final Map<String, dynamic> data;
  SafetyEvent(this.data);
  String get id => data['id'] as String;
  String get title => data['title'] as String;
  String get description => data['description'] as String;
  int get revision =>
      (data['_incident'] as Map?)?['revision'] as int? ??
      data['revision'] as int;
  String? get incidentId => (data['_incident'] as Map?)?['id'] as String?;
  List<SafetyEvent> get reports =>
      (data['_reports'] as List?)?.cast<SafetyEvent>() ?? [this];
  bool get hasConflictingReports =>
      (data['_incident'] as Map?)?['hasConflictingReports'] == true;
  String? get sourceSummary =>
      sources.length > 1 ? 'Komunikaty z ${sources.length} źródeł' : null;
  bool get isWczk => sources.any((s) => s['id'].toString().startsWith('WCZK-'));
  List<String> get areas => List<String>.from(data['regions'] as List);
  List<Map<String, dynamic>> get sources {
    final items = data['_reports'] == null
        ? (data['sources'] as List).cast<Map>()
        : reports.expand((e) => (e.data['sources'] as List).cast<Map>());
    return {
      for (final s in items) s['id']: Map<String, dynamic>.from(s),
    }.values.toList();
  }

  bool get isRcb => sources.any((s) => s['id'] == 'RCB');
  bool get isRso => sources.any((s) => s['id'] == 'RSO');
  bool get hasPoint => data['latitude'] is num && data['longitude'] is num;
  String get provenance => sources.any((s) => s['tier'] == 1 || s['tier'] == 2)
      ? 'ŹRÓDŁO OFICJALNE'
      : 'OSINT';
  String get badge {
    if (data['verification'] == 'REFUTED') return 'INFORMACJA ZDEMENTOWANA';
    if (data['messageContext'] == 'EXERCISE') return 'ĆWICZENIA';
    if (data['messageContext'] == 'TEST') return 'TEST';
    final end = DateTime.tryParse(data['validTo'] as String? ?? '');
    if (data['lifecycle'] == 'EXPIRED' ||
        (data['lifecycle'] == 'ACTIVE' &&
            end != null &&
            end.isBefore(DateTime.now()))) {
      return 'TERMIN MINĄŁ';
    }
    return switch (data['lifecycle']) {
      'ACTIVE' => 'AKTYWNE WG ŹRÓDŁA',
      'SCHEDULED' => 'ZAPLANOWANE',
      'ENDED' || 'CANCELLED' => 'ZAKOŃCZONE',
      _ => 'WAŻNOŚĆ NIEUSTALONA',
    };
  }

  factory SafetyEvent.parse(dynamic input) {
    final m = Map<String, dynamic>.from(input as Map);
    for (final k in [
      'id',
      'title',
      'description',
      'lifecycle',
      'messageContext',
      'verification',
    ]) {
      if (m[k] is! String) throw const FormatException('Niepoprawny komunikat');
    }
    if (m['revision'] is! int ||
        m['regions'] is! List ||
        m['sources'] is! List ||
        (m['sources'] as List).isEmpty) {
      throw const FormatException('Niepoprawny komunikat');
    }
    for (final s in m['sources'] as List) {
      if (s is! Map ||
          s['name'] is! String ||
          s['url'] is! String ||
          s['id'] is! String ||
          s['tier'] is! int) {
        throw const FormatException('Niepoprawne źródło');
      }
    }
    for (final r in m['regions'] as List) {
      if (r is! String) throw const FormatException('Niepoprawny region');
    }
    for (final e in [('latitude', 90), ('longitude', 180)]) {
      final v = m[e.$1];
      if (v != null && (v is! num || !v.isFinite || v.abs() > e.$2)) {
        throw const FormatException('Niepoprawna lokalizacja');
      }
    }
    return SafetyEvent(m);
  }
}

class Snapshot {
  final Map<String, dynamic> data;
  final List<SafetyEvent> events;
  Snapshot._(this.data, this.events);
  List<SafetyEvent> get alertEvents {
    final byId = {for (final e in events) e.id: e};
    final grouped = <String>{};
    final cards = <SafetyEvent>[];
    for (final raw in data['incidents'] as List? ?? []) {
      final incident = Map<String, dynamic>.from(raw as Map);
      final reports = (incident['reports'] as List)
          .map(SafetyEvent.parse)
          .toList();
      if (!reports.any((e) => byId.containsKey(e.id))) continue;
      final primary = reports.firstWhere(
        (e) => e.id == incident['primaryEventId'],
      );
      grouped.addAll(reports.map((e) => e.id));
      cards.add(
        SafetyEvent({
          ...primary.data,
          '_incident': incident,
          '_reports': reports,
        }),
      );
    }
    return [...cards, ...events.where((e) => !grouped.contains(e.id))];
  }

  factory Snapshot.parse(String text) {
    final m = Map<String, dynamic>.from(jsonDecode(text) as Map);
    if (m['schemaVersion'] != 1 ||
        m['regionId'] is! String ||
        m['sources'] is! List ||
        m['events'] is! List) {
      throw const FormatException('Nieobsługiwany format');
    }
    final incidents = m['incidents'];
    if (incidents != null) {
      if (incidents is! List) {
        throw const FormatException('Niepoprawne incydenty');
      }
      final assigned = <String>{};
      for (final i in incidents) {
        if (i is! Map ||
            i['id'] is! String ||
            i['revision'] is! int ||
            i['reports'] is! List ||
            (i['reports'] as List).isEmpty ||
            i['primaryEventId'] is! String ||
            i['relatedEventIds'] is! List ||
            i['hasConflictingReports'] is! bool) {
          throw const FormatException('Niepoprawny incydent');
        }
        final reports = (i['reports'] as List).map(SafetyEvent.parse).toList();
        final ids = reports.map((e) => e.id).toSet();
        if (ids.length != reports.length ||
            !ids.contains(i['primaryEventId']) ||
            ids.length != (i['relatedEventIds'] as List).length ||
            !(i['relatedEventIds'] as List).every(ids.contains) ||
            ids.any(assigned.contains)) {
          throw const FormatException('Niespójne powiązania komunikatów');
        }
        assigned.addAll(ids);
      }
    }
    DateTime.parse(m['serverTime'] as String);
    for (final s in [m['status'], m['nationalStatus']]) {
      if (s is! Map ||
          s['displayText'] is! String ||
          ![
            'UNKNOWN',
            'NO_ACTIVE_WARNINGS',
            'CAUTION',
            'ACTIVE_DANGER',
          ].contains(s['hazardLevel'])) {
        throw const FormatException('Niepoprawny status');
      }
      DateTime.parse(s['validUntil'] as String);
    }
    for (final s in m['sources'] as List) {
      if (s is! Map ||
          s['name'] is! String ||
          s['url'] is! String ||
          s['state'] is! String ||
          s['maxAgeSeconds'] is! num) {
        throw const FormatException('Niepoprawny stan źródła');
      }
      if (s['lastSuccess'] != null) DateTime.parse(s['lastSuccess'] as String);
    }
    for (final raw in m['securityLevels'] as List? ?? []) {
      SecurityLevel.parse(raw);
    }
    for (final raw in m['nationalSecurityLevels'] as List? ?? []) {
      SecurityLevel.parse(raw);
    }
    if (m['radiation'] != null) {
      final radiation = RadiationData.parse(m['radiation']);
      if (radiation.data['regionId'] != m['regionId']) {
        throw const FormatException('Błędny region PAA');
      }
    }
    if (m['shelterPage'] != null) {
      final page = ShelterPage.parse(m['shelterPage']);
      if (page.region != m['regionId']) {
        throw const FormatException('Błędny region punktów');
      }
    }
    return Snapshot._(m, (m['events'] as List).map(SafetyEvent.parse).toList());
  }
  ShelterPage? get shelters => data['shelterPage'] == null
      ? null
      : ShelterPage.parse(data['shelterPage']);
  String get region => data['regionId'] as String;
  bool freshAt(DateTime now, {bool national = false}) =>
      now.isBefore(
        DateTime.parse(
          data[national ? 'nationalStatus' : 'status']['validUntil'] as String,
        ),
      ) &&
      !DateTime.parse(
        data['serverTime'] as String,
      ).isAfter(now.add(const Duration(seconds: 30)));
  String statusText(
    DateTime now, {
    required bool online,
    bool national = false,
  }) => online && freshAt(now, national: national)
      ? data[national ? 'nationalStatus' : 'status']['displayText'] as String
      : 'Brak bieżącej oceny sytuacji';
}

class WatchedLocation {
  final String id;
  final String label;
  final double latitude;
  final double longitude;
  final double radiusKm;
  final String? regionId;

  const WatchedLocation({
    required this.id,
    required this.label,
    required this.latitude,
    required this.longitude,
    required this.radiusKm,
    this.regionId,
  });

  factory WatchedLocation.parse(dynamic input) {
    final m = Map<String, dynamic>.from(input as Map);
    final id = m['id'], label = m['label'];
    final lat = m['latitude'], lon = m['longitude'], radius = m['radiusKm'];
    final regionId = m['regionId'];
    if (id is! String ||
        !RegExp(r'^loc-[1-9]\d*$').hasMatch(id) ||
        label is! String ||
        label.trim().isEmpty ||
        label.trim().length > 60 ||
        lat is! num ||
        lon is! num ||
        radius is! num ||
        !lat.isFinite ||
        !lon.isFinite ||
        !radius.isFinite ||
        lat.abs() > 90 ||
        lon.abs() > 180 ||
        radius < 1 ||
        radius > 100 ||
        (regionId != null &&
            (regionId is! String ||
                regionId == 'PL' ||
                !regions.containsKey(regionId)))) {
      throw const FormatException('Niepoprawna obserwowana lokalizacja');
    }
    return WatchedLocation(
      id: id,
      label: label.trim(),
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      radiusKm: radius.toDouble(),
      regionId: regionId as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'latitude': latitude,
    'longitude': longitude,
    'radiusKm': radiusKm,
    'regionId': regionId,
  };
}

class NearbySafetyEvent {
  final SafetyEvent event;
  final int distanceMeters;
  NearbySafetyEvent._(this.event, this.distanceMeters);

  factory NearbySafetyEvent.parse(dynamic input) {
    final m = Map<String, dynamic>.from(input as Map);
    if (m['relevance'] != 'NEARBY' ||
        m['distanceMeters'] is! int ||
        (m['distanceMeters'] as int) < 0 ||
        m['event'] == null) {
      throw const FormatException('Niepoprawne zdarzenie w pobliżu');
    }
    final event = SafetyEvent.parse(m['event']);
    if (!event.hasPoint && event.data['geometry'] == null) {
      throw const FormatException('Brak geometrii dla obliczonej odległości');
    }
    return NearbySafetyEvent._(event, m['distanceMeters'] as int);
  }

  String get distanceLabel => distanceMeters < 1000
      ? '$distanceMeters m'
      : '${(distanceMeters / 1000).toStringAsFixed(distanceMeters < 10000 ? 1 : 0)} km';
}

class AroundResult {
  final Map<String, dynamic> data;
  final List<NearbySafetyEvent> nearbyEvents;
  final List<SafetyEvent> regionalEvents;
  final List<NearestShelter> nearestShelters;
  final Map<String, dynamic>? shelterHealth;

  AroundResult._(
    this.data,
    this.nearbyEvents,
    this.regionalEvents,
    this.nearestShelters,
    this.shelterHealth,
  );

  factory AroundResult.parse(dynamic input) {
    final m = Map<String, dynamic>.from(input as Map);
    if (m['schemaVersion'] != 1 ||
        m['serverTime'] is! String ||
        m['query'] is! Map ||
        m['nearbyEvents'] is! List ||
        m['regionalEvents'] is! List ||
        m['nearestShelters'] is! Map ||
        m['coverage'] is! Map) {
      throw const FormatException('Niepoprawna odpowiedź Wokół mnie');
    }
    DateTime.parse(m['serverTime'] as String);
    final q = Map<String, dynamic>.from(m['query'] as Map);
    final lat = q['latitude'], lon = q['longitude'], radius = q['radiusKm'];
    if (lat is! num ||
        lon is! num ||
        radius is! num ||
        !lat.isFinite ||
        !lon.isFinite ||
        !radius.isFinite ||
        lat.abs() > 90 ||
        lon.abs() > 180 ||
        radius < 1 ||
        radius > 100 ||
        (q['regionId'] != null &&
            (q['regionId'] is! String ||
                q['regionId'] == 'PL' ||
                !regions.containsKey(q['regionId'])))) {
      throw const FormatException('Niepoprawne zapytanie lokalizacyjne');
    }
    final nearby = (m['nearbyEvents'] as List)
        .map(NearbySafetyEvent.parse)
        .toList();
    if (nearby.length > 50) {
      throw const FormatException('Za dużo zdarzeń w pobliżu');
    }
    for (var i = 1; i < nearby.length; i++) {
      if (nearby[i - 1].distanceMeters > nearby[i].distanceMeters) {
        throw const FormatException('Niepoprawna kolejność odległości');
      }
    }
    final regional = <SafetyEvent>[];
    for (final raw in m['regionalEvents'] as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      if (row['relevance'] != 'REGION_RELEVANT' || row['event'] == null) {
        throw const FormatException('Niepoprawny kontekst regionalny');
      }
      regional.add(SafetyEvent.parse(row['event']));
    }
    final shelterBlock = Map<String, dynamic>.from(m['nearestShelters'] as Map);
    if (shelterBlock['items'] is! List) {
      throw const FormatException('Niepoprawne najbliższe schronienia');
    }
    final shelters = (shelterBlock['items'] as List)
        .map(NearestShelter.parse)
        .toList();
    if (shelters.length > 3) {
      throw const FormatException('Za dużo najbliższych schronień');
    }
    final health = shelterBlock['health'];
    if (health != null && health is! Map) {
      throw const FormatException('Niepoprawny stan wykazu schronień');
    }
    final coverage = Map<String, dynamic>.from(m['coverage'] as Map);
    if (coverage['spatial'] != 'PARTIAL_GEOMETRY_ONLY' ||
        ![
          'NOT_REQUESTED',
          'EXPLICIT_NATIONAL_OR_PROVINCE_SCOPE_ONLY',
        ].contains(coverage['regional']) ||
        coverage['statement'] is! String) {
      throw const FormatException('Niepoprawne pokrycie lokalizacyjne');
    }
    return AroundResult._(
      m,
      nearby,
      regional,
      shelters,
      health == null ? null : Map<String, dynamic>.from(health),
    );
  }

  double get radiusKm => (data['query']['radiusKm'] as num).toDouble();
  String? get regionId => data['query']['regionId'] as String?;
}

class DataRepository {
  final SharedPreferences prefs;
  final http.Client client;
  int _generation = 0;
  final String buildApi;
  final bool developerSettingsEnabled;
  DataRepository(
    this.prefs, {
    http.Client? client,
    this.buildApi = const String.fromEnvironment('API_BASE_URL'),
    this.developerSettingsEnabled = const bool.fromEnvironment(
      'ENABLE_DEVELOPER_SETTINGS',
      defaultValue: kDebugMode,
    ),
  }) : client = client ?? http.Client();
  String get developerApi => prefs.getString('developer_api') ?? '';
  String get api =>
      (developerSettingsEnabled && developerApi.isNotEmpty
              ? developerApi
              : buildApi)
          .trim()
          .replaceAll(RegExp(r'/+$'), '');
  String get region => prefs.getString('region') ?? '04';
  static const watchedLocationsKey = 'watched_locations_v1';
  List<WatchedLocation> get watchedLocations {
    try {
      final raw = prefs.getString(watchedLocationsKey);
      if (raw == null) return const [];
      final list = jsonDecode(raw);
      if (list is! List || list.length > 20) return const [];
      final items = list.map(WatchedLocation.parse).toList();
      if (items.map((e) => e.id).toSet().length != items.length) {
        return const [];
      }
      return items;
    } catch (_) {
      return const [];
    }
  }

  Future<WatchedLocation> addWatchedLocation({
    required String label,
    required double latitude,
    required double longitude,
    double radiusKm = 20,
    String? regionId,
  }) async {
    final current = watchedLocations;
    if (current.length >= 20) throw StateError('WATCHED_LOCATION_LIMIT');
    final nextId = (prefs.getInt('watched_location_counter') ?? 0) + 1;
    final item = WatchedLocation.parse({
      'id': 'loc-$nextId',
      'label': label,
      'latitude': latitude,
      'longitude': longitude,
      'radiusKm': radiusKm,
      'regionId': regionId,
    });
    await prefs.setString(
      watchedLocationsKey,
      jsonEncode([...current.map((e) => e.toJson()), item.toJson()]),
    );
    await prefs.setInt('watched_location_counter', nextId);
    return item;
  }

  Future<void> removeWatchedLocation(String id) async {
    final next = watchedLocations.where((e) => e.id != id).toList();
    await prefs.setString(
      watchedLocationsKey,
      jsonEncode(next.map((e) => e.toJson()).toList()),
    );
  }

  bool get dark => prefs.getBool('dark') ?? true;
  Uri _apiUri() {
    if (api.isEmpty) throw const ApiFailure(ApiFailureKind.notConfigured);
    try {
      return validateApi(api);
    } catch (_) {
      throw const ApiFailure(ApiFailureKind.notConfigured);
    }
  }

  Future<http.Response> _get(
    Uri uri, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    try {
      return await client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(timeout);
    } on TimeoutException {
      throw const ApiFailure(ApiFailureKind.timeout);
    } on http.ClientException {
      throw const ApiFailure(ApiFailureKind.network);
    } catch (error) {
      if (error is ApiFailure) rethrow;
      throw const ApiFailure(ApiFailureKind.network);
    }
  }

  Future<http.Response> _postJson(
    Uri uri,
    Object body, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    try {
      return await client
          .post(
            uri,
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const ApiFailure(ApiFailureKind.timeout);
    } on http.ClientException {
      throw const ApiFailure(ApiFailureKind.network);
    } catch (error) {
      if (error is ApiFailure) rethrow;
      throw const ApiFailure(ApiFailureKind.network);
    }
  }

  Never _responseFailure(http.Response response) {
    if (response.statusCode == 429) {
      throw const ApiFailure(ApiFailureKind.rateLimited, 429);
    }
    if (response.statusCode >= 500) {
      throw ApiFailure(ApiFailureKind.server, response.statusCode);
    }
    throw ApiFailure(ApiFailureKind.invalidResponse, response.statusCode);
  }

  static Uri validateApi(String value) {
    final u = Uri.tryParse(value.trim());
    if (u == null ||
        u.scheme != 'https' ||
        u.host.isEmpty ||
        u.userInfo.isNotEmpty ||
        u.hasQuery ||
        u.hasFragment) {
      throw const FormatException(
        'Wymagany adres HTTPS bez loginu i parametrów',
      );
    }
    return u;
  }

  Future<void> setDeveloperApi(String value) async {
    if (!developerSettingsEnabled) {
      throw StateError('Developer Settings are disabled in this build');
    }
    if (value.trim().isNotEmpty) validateApi(value);
    ++_generation;
    await prefs.setString(
      'developer_api',
      value.trim().replaceAll(RegExp(r'/+$'), ''),
    );
  }

  Future<void> setRegion(String value) async {
    if (!regions.containsKey(value)) throw ArgumentError('Region');
    await prefs.setString('region', value);
  }

  String cacheKey(String r) => 'snapshot:$api:$r';
  Snapshot? cached(String r) {
    try {
      final b = prefs.getString(cacheKey(r));
      return b == null ? null : Snapshot.parse(b);
    } catch (_) {
      return null;
    }
  }

  Future<Snapshot> refresh(String r) async {
    final ticket = _generation, key = cacheKey(r);
    final u = _apiUri();
    final response = await _get(
      u.replace(
        path: '${u.path}/v1/snapshot',
        queryParameters: {'regionId': r},
      ),
    );
    if (response.statusCode != 200) _responseFailure(response);
    if (response.bodyBytes.length > 4 * 1024 * 1024) {
      throw const ApiFailure(ApiFailureKind.invalidResponse);
    }
    Snapshot s;
    try {
      s = Snapshot.parse(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw const ApiFailure(ApiFailureKind.invalidResponse);
    }
    if (s.region != r) throw const FormatException('Błędny region');
    if (ticket != _generation) {
      throw StateError(
        'Dane odrzucone po zmianie konfiguracji lub usunięciu kopii',
      );
    }
    await prefs.setString(key, jsonEncode(s.data));
    return s;
  }

  int get dataGeneration => _generation;
  String shelterCacheKey(String r) => 'shelters:$api:$r';
  ShelterPage? cachedShelters(String r) {
    try {
      final text = prefs.getString(shelterCacheKey(r));
      final page = text == null ? null : ShelterPage.parse(jsonDecode(text));
      return page?.region == r ? page : null;
    } catch (_) {
      return null;
    }
  }

  Future<ShelterPage> refreshShelters(
    String r, {
    String query = '',
    int offset = 0,
    String? version,
  }) async {
    final ticket = _generation, key = shelterCacheKey(r);
    final u = _apiUri();
    final q = query.trim();
    final response = await _get(
      u.replace(
        path: '${u.path}/v1/shelters',
        queryParameters: {
          'regionId': r,
          'q': q,
          'offset': '$offset',
          'limit': '50',
          'version': ?version,
        },
      ),
    );
    if (response.statusCode == 409) {
      throw const ShelterVersionChanged();
    }
    if (response.statusCode != 200) _responseFailure(response);
    if (response.bodyBytes.length > 4 * 1024 * 1024) {
      throw const ApiFailure(ApiFailureKind.invalidResponse);
    }
    ShelterPage page;
    try {
      page = ShelterPage.parse(jsonDecode(utf8.decode(response.bodyBytes)));
    } catch (_) {
      throw const ApiFailure(ApiFailureKind.invalidResponse);
    }
    if (page.region != r ||
        page.query != q ||
        page.offset != offset ||
        (version != null && page.version != version)) {
      throw const FormatException('Błędny zakres punktów');
    }
    if (ticket != _generation) {
      throw StateError('Kopia usunięta lub zmieniony serwer');
    }
    await prefs.setString(key, jsonEncode(page.data));
    return page;
  }

  Future<NearestSheltersResult> nearestShelters(
    double latitude,
    double longitude, {
    int limit = 3,
  }) async {
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180 ||
        limit < 1 ||
        limit > 10) {
      throw const ApiFailure(ApiFailureKind.invalidResponse);
    }
    final u = _apiUri();
    final response = await _get(
      u.replace(
        path: '${u.path}/v1/shelters/nearest',
        queryParameters: {
          'lat': '$latitude',
          'lon': '$longitude',
          'limit': '$limit',
        },
      ),
    );
    if (response.statusCode != 200) _responseFailure(response);
    if (response.bodyBytes.length > 2 * 1024 * 1024) {
      throw const ApiFailure(ApiFailureKind.invalidResponse);
    }
    try {
      return NearestSheltersResult.parse(
        jsonDecode(utf8.decode(response.bodyBytes)),
      );
    } catch (_) {
      throw const ApiFailure(ApiFailureKind.invalidResponse);
    }
  }

  Future<AroundResult> around(
    double latitude,
    double longitude, {
    double radiusKm = 20,
    String? regionId,
  }) async {
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        !radiusKm.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180 ||
        radiusKm < 1 ||
        radiusKm > 100 ||
        (regionId != null &&
            (regionId == 'PL' || !regions.containsKey(regionId)))) {
      throw const ApiFailure(ApiFailureKind.invalidResponse);
    }
    final u = _apiUri();
    final response = await _postJson(u.replace(path: '${u.path}/v1/around'), {
      'latitude': latitude,
      'longitude': longitude,
      'radiusKm': radiusKm,
      'regionId': ?regionId,
    });
    if (response.statusCode != 200) _responseFailure(response);
    if (response.bodyBytes.length > 4 * 1024 * 1024) {
      throw const ApiFailure(ApiFailureKind.invalidResponse);
    }
    try {
      final result = AroundResult.parse(
        jsonDecode(utf8.decode(response.bodyBytes)),
      );
      final q = Map<String, dynamic>.from(result.data['query'] as Map);
      if (((q['latitude'] as num).toDouble() - latitude).abs() > 1e-9 ||
          ((q['longitude'] as num).toDouble() - longitude).abs() > 1e-9 ||
          ((q['radiusKm'] as num).toDouble() - radiusKm).abs() > 1e-9 ||
          q['regionId'] != regionId) {
        throw const FormatException('Niespójna odpowiedź lokalizacyjna');
      }
      return result;
    } catch (_) {
      throw const ApiFailure(ApiFailureKind.invalidResponse);
    }
  }

  Future<List<Map<String, dynamic>>> eventTimeline(
    String id, {
    bool incident = false,
  }) async {
    if (id.isEmpty || id.length > 150) {
      throw const FormatException('Błędny identyfikator');
    }
    final u = _apiUri();
    final response = await _get(
      u.replace(
        path:
            '${u.path}/v1/${incident ? 'incidents' : 'events'}/${Uri.encodeComponent(id)}/timeline',
      ),
    );
    if (response.statusCode != 200) _responseFailure(response);
    if (response.bodyBytes.length > 2 * 1024 * 1024) {
      throw const ApiFailure(ApiFailureKind.invalidResponse);
    }
    final raw = jsonDecode(utf8.decode(response.bodyBytes));
    if (raw is! List) throw const FormatException('Niepoprawna historia');
    return raw.map((item) {
      if (item is! Map ||
          item['payload'] is! Map ||
          item['recorded_at'] is! String ||
          item['reason'] is! String) {
        throw const FormatException('Niepoprawna historia');
      }
      final payload = Map<String, dynamic>.from(item['payload'] as Map);
      SafetyEvent.parse(payload);
      DateTime.parse(item['recorded_at'] as String);
      return Map<String, dynamic>.from(item);
    }).toList();
  }

  Future<void> clearData() async {
    ++_generation;
    for (final k
        in prefs
            .getKeys()
            .where(
              (k) =>
                  k.startsWith('snapshot:') ||
                  k.startsWith('seen:') ||
                  k.startsWith('shelters:') ||
                  k.startsWith('map:'),
            )
            .toList()) {
      await prefs.remove(k);
    }
  }
}

String stamp(dynamic value) {
  if (value is! String) return 'Nie podano';
  final d = DateTime.tryParse(value)?.toLocal();
  if (d == null) return 'Nie podano';
  return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
