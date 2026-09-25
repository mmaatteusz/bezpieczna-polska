import 'package:flutter/material.dart';

import '../model.dart';
import '../ui/safety_event_card.dart';

class AlertsScreen extends StatefulWidget {
  final List<SafetyEvent> events;
  final void Function(SafetyEvent) onOpenEvent;
  final Future<void> Function() onRefresh;

  const AlertsScreen({
    super.key,
    required this.events,
    required this.onOpenEvent,
    required this.onRefresh,
  });

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  String query = '';
  String lifecycle = 'Aktywne';
  String category = 'Wszystkie';

  bool _isExpired(SafetyEvent event) {
    final end = DateTime.tryParse(event.data['validTo']?.toString() ?? '');
    return end != null && end.isBefore(DateTime.now());
  }

  bool _lifecycleMatches(SafetyEvent event) {
    final state = event.data['lifecycle']?.toString();
    final expired = _isExpired(event);
    return switch (lifecycle) {
      'Aktywne' => state == 'ACTIVE' && !expired,
      'Zakończone' =>
        ['ENDED', 'CANCELLED', 'EXPIRED'].contains(state) || expired,
      _ => true,
    };
  }

  String _categoryOf(SafetyEvent event) {
    final type = event.data['eventType']?.toString();
    if (event.sources.any(
          (s) => s['id'] == 'IMGW_METEO' || s['id'] == 'IMGW_HYDRO',
        ) ||
        type == 'WEATHER') {
      return 'Pogoda';
    }
    if (type == 'CYBER') return 'Cyber';
    if (type == 'BORDER') return 'Granica';
    if ([
      'FIRE',
      'EXPLOSION',
      'HAZMAT',
      'RESCUE',
      'PUBLIC_SAFETY',
      'EVACUATION',
    ].contains(type)) {
      return 'Bezpieczeństwo';
    }
    return 'Inne';
  }

  @override
  Widget build(BuildContext context) {
    final needle = query.trim().toLowerCase();
    final list = widget.events.where((event) {
      final text =
          '${event.title} ${event.description} ${safetySourceLabel(event)}'
              .toLowerCase();
      return _lifecycleMatches(event) &&
          (category == 'Wszystkie' || _categoryOf(event) == category) &&
          text.contains(needle);
    }).toList();

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        key: const PageStorageKey('alerts'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          TextField(
            decoration: const InputDecoration(
              hintText: 'Szukaj alertu',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => query = value),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['Aktywne', 'Wszystkie', 'Zakończone']
                .map(
                  (value) => ChoiceChip(
                    label: Text(value),
                    selected: lifecycle == value,
                    onSelected: (_) => setState(() => lifecycle = value),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final value in [
                  'Wszystkie',
                  'Pogoda',
                  'Bezpieczeństwo',
                  'Cyber',
                  'Granica',
                  'Inne',
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(value),
                      selected: category == value,
                      onSelected: (_) => setState(() => category = value),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${list.length} komunikatów',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 6),
          if (list.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.notifications_none_outlined),
                title: Text('Brak alertów dla wybranych filtrów'),
                subtitle: Text('Zmień filtr albo wyszukiwane hasło.'),
              ),
            )
          else
            ...list.map(
              (event) => SafetyEventCard(
                event: event,
                onTap: () => widget.onOpenEvent(event),
              ),
            ),
        ],
      ),
    );
  }
}
