import 'package:flutter/material.dart';

import 'model.dart';

class StatusExplanation extends StatelessWidget {
  final Map status;
  final List<SafetyEvent> events;
  const StatusExplanation({
    super.key,
    required this.status,
    required this.events,
  });

  static const labels = <String, String>{
    'OFFICIAL_ACTIVE_WARNING':
        'Aktywne oficjalne ostrzeżenie dotyczące tego obszaru.',
    'OFFICIAL_CAUTION':
        'Obowiązuje istotne oficjalne ostrzeżenie wymagające ostrożności.',
    'LAST_KNOWN_WARNING':
        'Było aktywne zagrożenie, a źródło nie potwierdziło jeszcze jego zakończenia.',
    'ADMINISTRATIVE_READINESS_LEVELS':
        'Obowiązują stopnie alarmowe lub CRP. To poziom gotowości administracji, nie automatyczne potwierdzenie bezpośredniego zagrożenia.',
    'INCOMPLETE_SOURCE_COVERAGE':
        'Nie wszystkie wymagane źródła dostarczają obecnie kompletne i świeże dane.',
  };

  @override
  Widget build(BuildContext context) {
    final reasons = (status['reasonCodes'] as List? ?? const [])
        .whereType<String>()
        .toList();
    final supporting = (status['supportingEventIds'] as List? ?? const [])
        .whereType<String>()
        .toSet();
    final lastKnown = (status['lastKnownEventIds'] as List? ?? const [])
        .whereType<String>()
        .toSet();
    final related = events
        .where((e) => supporting.contains(e.id) || lastKnown.contains(e.id))
        .toList();

    final coverage = switch (status['coverageState']) {
      'COMPLETE_FOR_CONFIGURED_SCOPE' =>
        'Kompletne dla skonfigurowanego zakresu źródeł',
      'PARTIAL' => 'Częściowe',
      'STALE' => 'Nieaktualne',
      'UNAVAILABLE' => 'Niedostępne',
      _ => 'Nieustalone',
    };

    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      title: const Text('Dlaczego taki status?'),
      subtitle: Text('Pokrycie danych: $coverage'),
      children: [
        ...((status['supportingIncidents'] as List?) ?? []).whereType<Map>().map(
          (i) => ListTile(
            title: Text(
              'Jeden incydent • ${(i['sourceIds'] as List).join(' + ')}',
            ),
            subtitle: Text(
              i['hasConflictingReports'] == true
                  ? 'Źródła zawierają różniące się komunikaty.'
                  : 'Powiązane komunikaty nie zwiększają wielokrotnie oceny zagrożenia.',
            ),
          ),
        ),
        if (reasons.isEmpty)
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Brak dodatkowego uzasadnienia. Status wynika z aktualności monitorowanych źródeł.',
            ),
          ),
        ...reasons.map(
          (code) => ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.info_outline, size: 20),
            title: Text(labels[code] ?? code),
          ),
        ),
        if (related.isNotEmpty) ...[
          const Divider(),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Komunikaty wpływające na ocenę:'),
          ),
          ...related.map(
            (e) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                lastKnown.contains(e.id) ? Icons.history : Icons.campaign,
                size: 20,
              ),
              title: Text(e.title),
              subtitle: Text(e.badge),
            ),
          ),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Reguły: ${status['rulesetVersion'] ?? 'nie podano'} • Ocena: ${stamp(status['evaluatedAt'])}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
