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

  String effectiveStateOf(Map<String, dynamic> source) {
    final state = stateOf(source);
    if (source['enabled'] == false) return 'NOT_CONFIGURED';
    if (state == 'HEALTHY' && source['complete'] != true) return 'DEGRADED';
    return state;
  }

  String label(String state) => switch (state) {
    'HEALTHY' => 'HEALTHY • aktualne',
    'STALE' => 'STALE • nieaktualne',
    'DEGRADED' => 'PARTIAL • niepełne',
    'BROKEN' => 'DOWN • niedostępne',
    'NOT_CONFIGURED' => 'NOT_CONFIGURED • niepodłączone',
    _ => 'Stan nieustalony',
  };

  String explanation(String state) => switch (state) {
    'HEALTHY' => 'Źródło dostarcza świeże dane.',
    'STALE' =>
      'Istnieje ostatnia poprawna kopia, ale jej aktualność nie jest już potwierdzona.',
    'DEGRADED' =>
      'Źródło działa częściowo. Aplikacja nie zakłada, że brakujące dane oznaczają brak zagrożenia.',
    'BROKEN' =>
      'Nie udało się pobrać bieżących danych. Ostatnia poprawna kopia może nadal być widoczna jako STALE.',
    'NOT_CONFIGURED' =>
      'Ta integracja nie dostarcza obecnie danych w tej wersji aplikacji.',
    _ => 'Brak wystarczających informacji o aktualności tego źródła.',
  };

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
    final healthy = sources.where((s) => effectiveStateOf(s) == 'HEALTHY').length;
    final stale = sources.where((s) => effectiveStateOf(s) == 'STALE').length;
    final partial = sources
        .where((s) => effectiveStateOf(s) == 'DEGRADED')
        .length;
    final down = sources.where((s) => effectiveStateOf(s) == 'BROKEN').length;
    final notConfigured = sources
        .where((s) => effectiveStateOf(s) == 'NOT_CONFIGURED')
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
                    'Aktualność danych',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Aplikacja rozróżnia świeże dane, ostatnią poprawną kopię i brak połączenia. Brak danych nigdy nie jest prezentowany jako potwierdzenie bezpieczeństwa.',
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _metric(
                        context,
                        Icons.check_circle_outline,
                        'HEALTHY • aktualne',
                        healthy,
                      ),
                      _metric(
                        context,
                        Icons.schedule_outlined,
                        'STALE • nieaktualne',
                        stale,
                      ),
                      _metric(
                        context,
                        Icons.warning_amber_outlined,
                        'PARTIAL • niepełne',
                        partial,
                      ),
                      _metric(
                        context,
                        Icons.error_outline,
                        'DOWN • niedostępne',
                        down,
                      ),
                      _metric(
                        context,
                        Icons.link_off_outlined,
                        'NOT_CONFIGURED • niepodłączone',
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
            final effectiveState = effectiveStateOf(source);
            final fallback = source['fallback'];
            return Card(
              child: ExpansionTile(
                leading: Icon(icon(effectiveState)),
                title: Text(
                  source['name']?.toString() ?? source['id'].toString(),
                ),
                subtitle: Text(
                  '${label(effectiveState)}\nOstatnia poprawna synchronizacja: ${stamp(source['lastSuccessfulSyncAt'] ?? source['lastSuccess'])}',
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(explanation(effectiveState)),
                  ),
                  const SizedBox(height: 10),
                  _row(
                    'Ostatnia próba',
                    stamp(source['lastAttemptAt'] ?? source['lastAttempt']),
                  ),
                  _row('Ostatni element', stamp(source['lastItemTime'])),
                  if (source['dataDate'] != null)
                    _row('Data danych', source['dataDate'].toString()),
                  if (source['coverage'] != null)
                    _row('Zakres', source['coverage'].toString()),
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
