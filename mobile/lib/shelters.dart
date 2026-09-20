class ShelterVersionChanged implements Exception {
  const ShelterVersionChanged();
}

class ShelterPoint {
  final Map<String, dynamic> data;
  ShelterPoint._(this.data);
  factory ShelterPoint.parse(dynamic input) {
    final m = Map<String, dynamic>.from(input as Map);
    for (final field in [
      'id',
      'address',
      'municipality',
      'county',
      'regionId',
      'sourceType',
      'sourceAvailability',
      'dataDate',
      'sourceUpdatedAt',
    ]) {
      if (m[field] is! String) {
        throw const FormatException('Niepoprawny punkt');
      }
    }
    if (m['sourceId'] != 'SHELTERS' ||
        m['category'] != 'SHELTER_POINT' ||
        m['protectionClass'] != 'UNKNOWN' ||
        ![
          '24H',
          'ON_REQUEST',
          'LIMITED_HOURS',
          'UNKNOWN',
        ].contains(m['availability'])) {
      throw const FormatException('Niepoprawny rodzaj punktu');
    }
    for (final field in [('latitude', 49, 55), ('longitude', 14, 25)]) {
      final value = m[field.$1];
      if (value is! num ||
          !value.isFinite ||
          value < field.$2 ||
          value > field.$3) {
        throw const FormatException('Niepoprawna lokalizacja');
      }
    }
    DateTime.parse(m['sourceUpdatedAt'] as String);
    return ShelterPoint._(m);
  }
  String get address => data['address'] as String;
  String get availability => switch (data['availability']) {
    '24H' => 'Całodobowa wg źródła',
    'ON_REQUEST' => 'Na żądanie',
    'LIMITED_HOURS' => 'Określone godziny — godzin nie podano',
    _ => 'Dostępność nieustalona',
  };
}

class ShelterPage {
  final Map<String, dynamic> data;
  final List<ShelterPoint> items;
  ShelterPage._(this.data, this.items);
  factory ShelterPage.parse(dynamic input) {
    final m = Map<String, dynamic>.from(input as Map);
    if (m['schemaVersion'] != 1 ||
        m['regionId'] is! String ||
        m['query'] is! String ||
        m['items'] is! List ||
        m['total'] is! int ||
        m['offset'] is! int ||
        m['limit'] is! int ||
        m['hasMore'] is! bool) {
      throw const FormatException('Niepoprawna lista punktów');
    }
    DateTime.parse(m['serverTime'] as String);
    final items = (m['items'] as List).map(ShelterPoint.parse).toList();
    final total = m['total'] as int,
        offset = m['offset'] as int,
        limit = m['limit'] as int;
    if (total < 0 ||
        offset < 0 ||
        limit < 1 ||
        limit > 500 ||
        items.length > limit ||
        items.length > total ||
        m['hasMore'] != (offset + items.length < total) ||
        items.map((p) => p.data['id']).toSet().length != items.length ||
        (m['regionId'] != 'PL' &&
            items.any((p) => p.data['regionId'] != m['regionId']))) {
      throw const FormatException('Niespójna lista punktów');
    }
    final version = m['version'];
    if ((version != null &&
            (version is! String ||
                !RegExp(r'^[a-f0-9]{64}$').hasMatch(version))) ||
        (items.isNotEmpty && version == null)) {
      throw const FormatException('Brak wersji danych');
    }
    final h = m['health'];
    if (h != null) {
      if (h is! Map ||
          h['id'] != 'SHELTERS' ||
          h['state'] is! String ||
          h['maxAgeSeconds'] is! num) {
        throw const FormatException('Niepoprawny stan źródła');
      }
      if (h['lastSuccess'] != null) {
        DateTime.parse(h['lastSuccess'] as String);
      }
    }
    return ShelterPage._(m, items);
  }
  String get region => data['regionId'] as String;
  String get query => data['query'] as String;
  int get total => data['total'] as int;
  int get offset => data['offset'] as int;
  int get limit => data['limit'] as int;
  bool get hasMore => data['hasMore'] as bool;
  String? get version => data['version'] as String?;
  Map<String, dynamic>? get health => data['health'] == null
      ? null
      : Map<String, dynamic>.from(data['health'] as Map);
  bool freshAt(DateTime now) {
    final h = health;
    if (h == null || h['state'] != 'HEALTHY' || h['complete'] != true) {
      return false;
    }
    final success = DateTime.tryParse(h['lastSuccess'] as String? ?? '');
    final source = DateTime.tryParse(h['sourceUpdatedAt'] as String? ?? '');
    return success != null &&
        source != null &&
        !success.isAfter(now.add(const Duration(seconds: 30))) &&
        now.difference(success).inSeconds < (h['maxAgeSeconds'] as num) &&
        now.difference(source) < const Duration(days: 14);
  }
}
