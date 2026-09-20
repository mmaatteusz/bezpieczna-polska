import 'dart:convert';
import 'shelters.dart';
import 'security_levels.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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
  int get revision => data['revision'] as int;
  List<String> get areas => List<String>.from(data['regions'] as List);
  List<Map<String, dynamic>> get sources => (data['sources'] as List)
      .map((s) => Map<String, dynamic>.from(s as Map))
      .toList();
  bool get isRcb => sources.any((s) => s['id'] == 'RCB');
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
  factory Snapshot.parse(String text) {
    final m = Map<String, dynamic>.from(jsonDecode(text) as Map);
    if (m['schemaVersion'] != 1 ||
        m['regionId'] is! String ||
        m['sources'] is! List ||
        m['events'] is! List) {
      throw const FormatException('Nieobsługiwany format');
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
  bool get dark => prefs.getBool('dark') ?? true;
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
    final u = validateApi(api);
    final response = await client
        .get(
          u.replace(
            path: '${u.path}/v1/snapshot',
            queryParameters: {'regionId': r},
          ),
          headers: {'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200 ||
        response.bodyBytes.length > 4 * 1024 * 1024) {
      throw const FormatException('Błąd odpowiedzi serwera');
    }
    final s = Snapshot.parse(utf8.decode(response.bodyBytes));
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
    final u = validateApi(api);
    final q = query.trim();
    final response = await client
        .get(
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
          headers: {'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 409) {
      throw const ShelterVersionChanged();
    }
    if (response.statusCode != 200 ||
        response.bodyBytes.length > 4 * 1024 * 1024) {
      throw const FormatException('Błąd odpowiedzi serwera');
    }
    final page = ShelterPage.parse(jsonDecode(utf8.decode(response.bodyBytes)));
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
