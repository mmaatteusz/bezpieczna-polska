import 'package:flutter/material.dart';
import 'model.dart';

class RadiationData {
  final Map<String, dynamic> data;
  RadiationData._(this.data);
  factory RadiationData.parse(dynamic value) {
    if (value is! Map) throw const FormatException('Niepoprawne dane PAA');
    final m = Map<String, dynamic>.from(value);
    if (m['schemaVersion'] != 1 ||
        m['regionId'] is! String ||
        ![
          'UNAVAILABLE',
          'ACTIVE',
          'UNDETERMINED',
          'NO_ACTIVE_MESSAGE_IN_WINDOW',
        ].contains(m['communicationState']) ||
        ![
          'NOT_CONFIGURED',
          'NO_DATA',
          'FRESH',
          'STALE',
        ].contains(m['measurementState']) ||
        m['messages'] is! List ||
        m['measurements'] is! List ||
        m['sourceHealth'] is! List ||
        m['measuredValuesAffectHazard'] != false) {
      throw const FormatException('Niepoprawny format PAA');
    }
    for (final event in m['messages'] as List) {
      final e = SafetyEvent.parse(event);
      if (e.data['eventType'] != 'RADIATION' ||
          !e.sources.any((s) => s['id'] == 'PAA')) {
        throw const FormatException('Niepoprawny komunikat PAA');
      }
    }
    for (final item in m['measurements'] as List) {
      if (item is! Map ||
          item['stationId'] is! String ||
          item['name'] is! String ||
          item['value'] is! num ||
          !(item['value'] as num).isFinite ||
          item['value'] < 0 ||
          !['nSv/h', 'µSv/h'].contains(item['unit']) ||
          !['FRESH', 'STALE'].contains(item['freshness'])) {
        throw const FormatException('Niepoprawny pomiar PAA');
      }
      for (final key in ['measuredAt', 'sourceUpdatedAt']) {
        DateTime.parse(item[key] as String);
      }
      final lat = item['latitude'], lon = item['longitude'];
      if ((lat == null) != (lon == null) ||
          (lat != null &&
              (lat is! num ||
                  lon is! num ||
                  !lat.isFinite ||
                  !lon.isFinite ||
                  lat < 49 ||
                  lat > 55 ||
                  lon < 14 ||
                  lon > 24.2))) {
        throw const FormatException('Niepoprawna geometria PAA');
      }
    }
    return RadiationData._(m);
  }
  bool channelFresh(String id, DateTime now, bool online) {
    if (!online) return false;
    for (final h in data['sourceHealth'] as List) {
      if (h is! Map || h['id'] != id || h['state'] != 'HEALTHY') continue;
      final date = DateTime.tryParse(h['lastSuccess'] as String? ?? '');
      return date != null &&
          h['maxAgeSeconds'] is num &&
          !date.isAfter(now.add(const Duration(seconds: 30))) &&
          now.difference(date).inSeconds < h['maxAgeSeconds'];
    }
    return false;
  }

  String communicationText(DateTime now, bool online) {
    if (!channelFresh('PAA', now, online)) {
      return 'Komunikaty PAA: aktualność niepotwierdzona — STALE / brak połączenia';
    }
    return switch (data['communicationState']) {
      'ACTIVE' => 'Aktywny komunikat PAA o zagrożeniu',
      'UNDETERMINED' =>
        'Komunikat PAA wymaga sprawdzenia — stan zagrożenia nieustalony',
      'NO_ACTIVE_MESSAGE_IN_WINDOW' =>
        'Brak aktywnego komunikatu PAA w pobranym zakresie',
      _ => 'Komunikaty PAA: źródło niedostępne',
    };
  }

  String measurementText(DateTime now, bool online) {
    if (data['measurementState'] == 'NOT_CONFIGURED') {
      return 'Pomiary PAA: integracja niedostępna — format źródła niezweryfikowany';
    }
    final items = data['measurements'] as List;
    if (items.isEmpty) return 'Pomiary PAA: brak danych';
    final fresh =
        channelFresh('PAA_MEASUREMENTS', now, online) &&
        items.every(
          (p) =>
              p['freshness'] == 'FRESH' &&
              now
                      .difference(DateTime.parse(p['measuredAt'] as String))
                      .inSeconds <
                  900 &&
              !DateTime.parse(
                p['measuredAt'] as String,
              ).isAfter(now.add(const Duration(seconds: 30))),
        );
    return fresh
        ? 'Dane pomiarowe aktualne'
        : 'Dane pomiarowe STALE — ostatnia zapisana kopia';
  }
}

class RadiationPanel extends StatelessWidget {
  final Snapshot? snapshot;
  final bool online;
  final void Function(String) openSource;
  const RadiationPanel({
    super.key,
    required this.snapshot,
    required this.online,
    required this.openSource,
  });
  @override
  Widget build(BuildContext context) {
    final raw = snapshot?.data['radiation'];
    final radiation = raw == null ? null : RadiationData.parse(raw);
    final now = DateTime.now();
    final messages = (radiation?.data['messages'] as List? ?? []).cast<Map>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PAA • sytuacja radiacyjna',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              radiation?.communicationText(now, online) ??
                  'Komunikaty PAA: brak danych',
            ),
            Text(
              radiation?.measurementText(now, online) ??
                  'Pomiary PAA: brak danych',
            ),
            const Text(
              'Pomiar promieniowania nie jest alarmem. Archiwum publikacji nie stanowi pełnej listy aktywnych zagrożeń.',
            ),
            for (final message in messages.take(3))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(message['title'] as String),
                subtitle: Text(
                  'Publikacja: ${message['publicationDate'] ?? stamp(message['publishedAt'])} • ${message['lifecycle']}',
                ),
                onTap: () => openSource(
                  (message['sources'] as List).first['url'] as String,
                ),
              ),
            TextButton(
              onPressed: () =>
                  openSource('https://www.gov.pl/web/paa/aktualnosci2'),
              child: const Text('Oficjalne komunikaty PAA'),
            ),
          ],
        ),
      ),
    );
  }
}
