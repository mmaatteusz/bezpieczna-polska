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
    return widget.repository.eventTimeline(widget.event.id);
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
          ...e.sources.map(
            (s) => OutlinedButton.icon(
              onPressed: () => widget.openLink(s['url'] as String),
              icon: const Icon(Icons.open_in_new),
              label: Text(s['name'] as String),
            ),
          ),
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
                    subtitle: const Text(
                      'Treść komunikatu pozostaje dostępna. Spróbuj ponownie po połączeniu z backendem.',
                    ),
                    trailing: IconButton(
                      tooltip: 'Ponów',
                      onPressed: () => setState(() => timeline = _loadTimeline()),
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
                  final payload = Map<String, dynamic>.from(row['payload'] as Map);
                  final revision = payload['revision'];
                  final lifecycle = payload['lifecycle'] as String? ?? 'UNKNOWN';
                  final verification = payload['verification'] as String? ?? 'UNVERIFIED';
                  final correction = payload['correction'] as String?;
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.history),
                      title: Text('Wersja $revision • $lifecycle'),
                      subtitle: Text(
                        '${stamp(row['recorded_at'])}\n'
                        '${row['reason']}\n'
                        'Weryfikacja: $verification'
                        '${correction == null ? '' : '\nKorekta: $correction'}',
                      ),
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
