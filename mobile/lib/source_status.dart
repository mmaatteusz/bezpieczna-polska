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

  String label(String state) => switch (state) {
    'HEALTHY' => 'AKTUALNE',
    'STALE' => 'STALE • NIEAKTUALNE',
    'DEGRADED' => 'NIEPEŁNE',
    'BROKEN' => 'BŁĄD',
    'NOT_CONFIGURED' => 'NIEPODŁĄCZONE',
    _ => state,
  };

  String fallbackLabel(dynamic value) => switch (value) {
    'PRIMARY_OFFICIAL_SOURCE' => 'Bieżące oficjalne źródło',
    'SECONDARY_OFFICIAL_SOURCE' => 'Oficjalne archiwum zapasowe',
    'LAST_KNOWN_GOOD_COPY' => 'Ostatnia poprawna kopia',
    'NONE' => 'Brak danych',
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
    return Scaffold(
      appBar: AppBar(title: const Text('Źródła i aktualność')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Stan źródła opisuje możliwość pobierania świeżych danych. STALE oznacza, że ostatnia poprawna kopia istnieje, ale jej aktualność nie jest już potwierdzona.',
          ),
          const SizedBox(height: 12),
          ...sources.map((source) {
            final state =
                (source['healthStatus'] ?? source['state'] ?? 'UNKNOWN')
                    .toString();
            final enabled = source['enabled'] != false;
            final complete = source['complete'] == true;
            final displayState = !enabled
                ? 'NIEPODŁĄCZONE • ŚWIADOMIE POZA ZAKRESEM'
                : state == 'HEALTHY' && !complete
                ? 'AKTYWNE • CZĘŚCIOWE'
                : label(state);
            final fallback = source['fallback'];
            return Card(
              child: ExpansionTile(
                leading: Icon(icon(state)),
                title: Text(
                  source['name']?.toString() ?? source['id'].toString(),
                ),
                subtitle: Text(
                  '$displayState\nOstatnia poprawna synchronizacja: ${stamp(source['lastSuccessfulSyncAt'] ?? source['lastSuccess'])}',
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  if (source['integrationNote'] is String)
                    Text(source['integrationNote'] as String),
                  _row(
                    'Ostatnia próba',
                    stamp(source['lastAttemptAt'] ?? source['lastAttempt']),
                  ),
                  _row('Ostatni element', stamp(source['lastItemTime'])),
                  if (source['dataDate'] != null)
                    _row('Data danych', source['dataDate'].toString()),
                  if (source['sourceUpdatedAt'] != null)
                    _row(
                      'Aktualizacja źródła',
                      stamp(source['sourceUpdatedAt']),
                    ),
                  if (source['coverage'] != null)
                    _row('Zakres', source['coverage'].toString()),
                  if (source['itemCount'] != null)
                    _row('Liczba elementów', source['itemCount'].toString()),
                  if (source['failureCount'] != null)
                    _row('Kolejne błędy', source['failureCount'].toString()),
                  if (source['errorCode'] != null)
                    _row('Kod diagnostyczny', source['errorCode'].toString()),
                  if (source['adapterVersion'] != null)
                    _row('Adapter', source['adapterVersion'].toString()),
                  if (fallback is Map) ...[
                    _row('Tryb danych', fallbackLabel(fallback['selected'])),
                    if (fallback['reason'] != null)
                      _row('Powód fallbacku', fallback['reason'].toString()),
                  ],
                  const SizedBox(height: 8),
                  if (source['url'] is String)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () => openLink(source['url'] as String),
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Otwórz źródło'),
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
