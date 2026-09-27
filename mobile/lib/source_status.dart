import 'package:flutter/material.dart';

import 'model.dart';

class SourceStatusPage extends StatelessWidget {
  final List<Map<String, dynamic>> sources;
  final Future<void> Function(String) openLink;
  const SourceStatusPage({
    super.key,
    required this.sources,
    required this.openLink,
  });

  String stateOf(Map<String, dynamic> source) =>
      (source['healthStatus'] ?? source['state'] ?? 'UNKNOWN').toString();

  String technicalStateOf(Map<String, dynamic> source) {
    if (source['enabled'] == false) return 'NOT_CONFIGURED';
    return stateOf(source);
  }

  String technicalLabel(String state) => switch (state) {
    'HEALTHY' => 'AKTUALNE • działa',
    'STALE' => 'NIEAKTUALNE • ostatnia kopia',
    'DEGRADED' => 'OGRANICZONE • działa częściowo',
    'BROKEN' => 'NIEDOSTĘPNE • błąd',
    'NOT_CONFIGURED' => 'NIEPODŁĄCZONE',
    _ => 'Stan nieustalony',
  };

  String technicalExplanation(String state) => switch (state) {
    'HEALTHY' => 'Połączenie ze źródłem działa i dane są świeże.',
    'STALE' =>
      'Istnieje ostatnia poprawna kopia, ale jej aktualność nie jest już potwierdzona.',
    'DEGRADED' =>
      'Źródło odpowiada, ale integracja zgłasza ograniczoną jakość lub niepełną synchronizację.',
    'BROKEN' =>
      'Nie udało się pobrać bieżących danych. Ostatnia poprawna kopia może nadal być dostępna.',
    'NOT_CONFIGURED' =>
      'Ta integracja nie dostarcza obecnie danych w tej wersji aplikacji.',
    _ => 'Brak wystarczających informacji o stanie technicznym źródła.',
  };

  String coverageType(dynamic value) => switch (value?.toString()) {
    'ACTIVE_WARNINGS' => 'aktywne ostrzeżenia',
    'RECENT_PUBLICATIONS' => 'ostatnie publikacje',
    'FACILITY_CATALOG' => 'katalog obiektów',
    'MEASUREMENT_NETWORK' => 'sieć pomiarowa',
    null => 'nieokreślony typ danych',
    final value => value,
  };

  String coverageLabel(Map<String, dynamic> source) {
    final type = coverageType(source['coverage']);
    if (source['complete'] == true) {
      return 'pełny dla obsługiwanego zakresu • $type';
    }
    return 'ograniczony • $type';
  }

  String coverageExplanation(Map<String, dynamic> source) {
    if (source['complete'] == true) {
      return 'Źródło deklaruje pełny zakres dla obsługiwanego typu danych.';
    }
    return 'Źródło nie jest kompletnym rejestrem wszystkich możliwych zdarzeń. '
        'To ograniczenie zakresu, a nie awaria połączenia.';
  }

  String fallbackLabel(dynamic value) => switch (value) {
    'PRIMARY_OFFICIAL_SOURCE' => 'Bieżące oficjalne źródło',
    'SECONDARY_OFFICIAL_SOURCE' => 'Oficjalne źródło zapasowe',
    'LAST_KNOWN_GOOD_COPY' => 'LAST KNOWN GOOD',
    'NONE' => 'Brak danych zapasowych',
    _ => value?.toString() ?? 'Nie podano',
  };

  IconData icon(String state) => switch (state) {
    'HEALTHY' => Icons.check_circle_outline,
    'STALE' => Icons.schedule_outlined,
    'DEGRADED' => Icons.warning_amber_outlined,
    'BROKEN' => Icons.error_outline,
    _ => Icons.link_off_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final working = sources
        .where(
          (s) => ['HEALTHY', 'DEGRADED'].contains(technicalStateOf(s)),
        )
        .length;
    final stale = sources.where((s) => technicalStateOf(s) == 'STALE').length;
    final down = sources.where((s) => technicalStateOf(s) == 'BROKEN').length;
    final notConfigured = sources
        .where((s) => technicalStateOf(s) == 'NOT_CONFIGURED')
        .length;

    return Scaffold(
      appBar: AppBar(title: const Text('Źródła danych')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Połączenie ze źródłami',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Stan techniczny i kompletność danych są pokazywane osobno. '
                    'Źródło może działać poprawnie, ale obejmować tylko część '
                    'publikowanych informacji.',
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _metric(
                        context,
                        Icons.check_circle_outline,
                        'Działa',
                        working,
                      ),
                      _metric(
                        context,
                        Icons.schedule_outlined,
                        'Nieaktualne',
                        stale,
                      ),
                      _metric(
                        context,
                        Icons.error_outline,
                        'Niedostępne',
                        down,
                      ),
                      if (notConfigured > 0)
                        _metric(
                          context,
                          Icons.link_off_outlined,
                          'Niepodłączone',
                          notConfigured,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (sources.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.hub_outlined),
                title: Text('Brak informacji o źródłach'),
                subtitle: Text(
                  'Stan źródeł pojawi się po pierwszej udanej synchronizacji.',
                ),
              ),
            ),
          ...sources.map((source) {
            final technicalState = technicalStateOf(source);
            final fallback = source['fallback'];
            return Card(
              child: ExpansionTile(
                leading: Icon(icon(technicalState)),
                title: Text(
                  source['name']?.toString() ?? source['id'].toString(),
                ),
                subtitle: Text(
                  '${technicalLabel(technicalState)}\n'
                  'Zakres danych: ${coverageLabel(source)}\n'
                  'Ostatnia poprawna synchronizacja: '
                  '${stamp(source['lastSuccessfulSyncAt'] ?? source['lastSuccess'])}',
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(technicalExplanation(technicalState)),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(coverageExplanation(source)),
                  ),
                  const SizedBox(height: 10),
                  _row(
                    'Ostatnia próba',
                    stamp(source['lastAttemptAt'] ?? source['lastAttempt']),
                  ),
                  _row('Ostatni element', stamp(source['lastItemTime'])),
                  if (source['dataDate'] != null)
                    _row('Data danych', source['dataDate'].toString()),
                  _row('Zakres danych', coverageLabel(source)),
                  if (source['itemCount'] != null)
                    _row('Liczba elementów', source['itemCount'].toString()),
                  if (fallback is Map)
                    _row('Używane dane', fallbackLabel(fallback['selected'])),
                  const SizedBox(height: 8),
                  if (source['url'] is String)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () => openLink(source['url'] as String),
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Otwórz oficjalne źródło'),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _metric(
    BuildContext context,
    IconData iconData,
    String label,
    int count,
  ) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(iconData, size: 18),
        const SizedBox(width: 6),
        Text('$label: $count'),
      ],
    ),
  );

  Widget _row(String name, String value) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 145, child: Text(name)),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
