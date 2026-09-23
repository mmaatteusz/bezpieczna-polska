import 'package:flutter/material.dart';

import 'model.dart';

class EventDetailsPage extends StatefulWidget {
  final SafetyEvent event;
  final DataRepository repository;
  final Future<void> Function(String) openLink;
  const EventDetailsPage({
    super.key,
    required this.event,
    required this.repository,
    required this.openLink,
  });

  @override
  State<EventDetailsPage> createState() => _EventDetailsPageState();
}

class _EventDetailsPageState extends State<EventDetailsPage> {
  late Future<List<Map<String, dynamic>>> timeline;

  @override
  void initState() {
    super.initState();
    timeline = _loadTimeline();
  }

  Future<List<Map<String, dynamic>>> _loadTimeline() async {
    if (widget.repository.api.isEmpty) return const [];
    return widget.repository.eventTimeline(
      widget.event.incidentId ?? widget.event.id,
      incident: widget.event.incidentId != null,
    );
  }

  String fieldLabel(String field) => switch (field) {
    'CREATED' => 'Utworzono zapis',
    'title' => 'Tytuł',
    'description' => 'Treść',
    'lifecycle' => 'Stan komunikatu',
    'verification' => 'Weryfikacja',
    'validFrom' => 'Ważny od',
    'validTo' => 'Ważny do',
    'correction' => 'Korekta / sprostowanie',
    'regions' => 'Obszar',
    _ => field,
  };

  String changeValue(String field, dynamic value) {
    if (value == null) return 'brak';
    if (field == 'validFrom' || field == 'validTo') return stamp(value);
    if (field == 'regions' && value is List) {
      return value.map((r) => regions[r] ?? r.toString()).join(', ');
    }
    if (field == 'lifecycle') {
      return switch (value) {
        'ACTIVE' => 'aktywne',
        'SCHEDULED' => 'zaplanowane',
        'ENDED' => 'zakończone',
        'CANCELLED' => 'odwołane',
        'EXPIRED' => 'termin minął',
        _ => value.toString(),
      };
    }
    if (field == 'verification') {
      return switch (value) {
        'CONFIRMED' => 'potwierdzone',
        'PROBABLE' => 'prawdopodobne',
        'UNVERIFIED' => 'niezweryfikowane',
        'REFUTED' => 'zdementowane',
        'DISPUTED' => 'sporne',
        _ => value.toString(),
      };
    }
    final text = value.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length > 220 ? '${text.substring(0, 220)}…' : text;
  }

  Widget badge(BuildContext context, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(text, style: Theme.of(context).textTheme.labelSmall),
  );

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    return Scaffold(
      appBar: AppBar(title: const Text('Szczegóły komunikatu')),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [badge(context, e.badge), badge(context, e.provenance)],
          ),
          if (e.sourceSummary != null) Text(e.sourceSummary!),
          if (e.hasConflictingReports)
            const Text(
              'Źródła różnią się stanem lub obszarem. Zakończenie albo sprostowanie w jednym źródle nie unieważnia pozostałych komunikatów.',
            ),
          const SizedBox(height: 20),
          Text(e.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          SelectableText(e.description),
          const SizedBox(height: 20),
          if (e.data['correction'] != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.fact_check_outlined),
                title: const Text('Korekta / sprostowanie'),
                subtitle: Text(e.data['correction'] as String),
              ),
            ),
          Text(
            'Publikacja: ${e.data['publishedAt'] == null ? (e.data['publicationDate'] ?? 'Nie podano') : stamp(e.data['publishedAt'])}',
          ),
          if (e.data['locationText'] != null)
            Text('Obszar według źródła: ${e.data['locationText']}'),
          Text('Pobrano: ${stamp(e.data['retrievedAt'])}'),
          Text('Od: ${stamp(e.data['validFrom'])}'),
          Text('Do: ${stamp(e.data['validTo'])}'),
          Text('Wersja: ${e.revision}'),
          const SizedBox(height: 12),
          if (e.sources.any((s) => s['id'] == 'IMGW_METEO' || s['id'] == 'IMGW_HYDRO'))
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Źródłem pochodzenia danych jest Instytut Meteorologii i Gospodarki Wodnej – Państwowy Instytut Badawczy. Dane Instytutu Meteorologii i Gospodarki Wodnej – Państwowego Instytutu Badawczego zostały przetworzone.',
              ),
            ),
          ...e.sources.map(
            (s) => OutlinedButton.icon(
              onPressed: () => widget.openLink(s['url'] as String),
              icon: const Icon(Icons.open_in_new),
              label: Text(s['name'] as String),
            ),
          ),
          if (e.reports.length > 1) ...[
            const SizedBox(height: 16),
            const Text('Komunikaty źródłowe'),
            ...e.reports.map(
              (report) => Card(
                child: ExpansionTile(
                  title: Text(report.sources.map((s) => s['name']).join(', ')),
                  subtitle: Text(
                    '${report.badge} • Publikacja: ${stamp(report.data['publishedAt'])}',
                  ),
                  childrenPadding: const EdgeInsets.all(16),
                  children: [
                    Text(report.title),
                    SelectableText(report.description),
                    Text(
                      'Obszar: ${report.data['locationText'] ?? report.areas.map((r) => regions[r] ?? r).join(', ')}',
                    ),
                    Text(
                      'Od: ${stamp(report.data['validFrom'])} • Do: ${stamp(report.data['validTo'])}',
                    ),
                    if (report.data['correction'] != null)
                      Text('Sprostowanie: ${report.data['correction']}'),
                    ...report.sources.map(
                      (s) => TextButton(
                        onPressed: () => widget.openLink(s['url'] as String),
                        child: Text(s['name'] as String),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            'Historia komunikatu',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: timeline,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LinearProgressIndicator();
              }
              if (snapshot.hasError) {
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.history_toggle_off),
                    title: const Text('Historia chwilowo niedostępna'),
                    subtitle: Text(apiFailureMessage(snapshot.error!)),
                    trailing: IconButton(
                      tooltip: 'Ponów',
                      onPressed: () =>
                          setState(() => timeline = _loadTimeline()),
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                );
              }
              final rows = snapshot.data ?? const [];
              if (rows.isEmpty) {
                return const Text(
                  'Brak dodatkowych zapisanych rewizji tego komunikatu.',
                );
              }
              return Column(
                children: rows.reversed.map((row) {
                  final payload = Map<String, dynamic>.from(
                    row['payload'] as Map,
                  );
                  final revision = payload['revision'];
                  final lifecycle =
                      payload['lifecycle'] as String? ?? 'UNKNOWN';
                  final verification =
                      payload['verification'] as String? ?? 'UNVERIFIED';
                  final correction = payload['correction'] as String?;
                  final changes = (row['changes'] as List? ?? const [])
                      .whereType<Map>()
                      .map((raw) => Map<String, dynamic>.from(raw))
                      .toList();
                  return Card(
                    child: ExpansionTile(
                      leading: Icon(
                        correction != null || verification == 'REFUTED'
                            ? Icons.fact_check_outlined
                            : Icons.history,
                      ),
                      title: Text(
                        '${(payload['sources'] as List).map((s) => (s as Map)['name']).join(', ')} • Wersja $revision • $lifecycle',
                      ),
                      subtitle: Text(
                        '${stamp(row['recorded_at'])} • ${row['actor'] ?? 'system'}\n${row['reason']}',
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      children: [
                        if (changes.isEmpty)
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Brak opisanych zmian pól.'),
                          ),
                        ...changes.map((change) {
                          final field = change['field']?.toString() ?? 'zmiana';
                          if (field == 'CREATED') {
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(
                                Icons.add_circle_outline,
                                size: 20,
                              ),
                              title: Text(fieldLabel(field)),
                            );
                          }
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.compare_arrows, size: 20),
                            title: Text(fieldLabel(field)),
                            subtitle: Text(
                              '${changeValue(field, change['from'])}\n→ ${changeValue(field, change['to'])}',
                            ),
                          );
                        }),
                        if (correction != null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Korekta: $correction',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
