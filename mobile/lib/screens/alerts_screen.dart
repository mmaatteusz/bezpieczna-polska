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

  bool _matchesTextAndCategory(SafetyEvent event) {
    final needle = query.trim().toLowerCase();
    final text =
        '${event.title} ${event.description} ${safetySourceLabel(event)}'
            .toLowerCase();
    return (category == 'Wszystkie' || _categoryOf(event) == category) &&
        text.contains(needle);
  }

  int _sortEvents(SafetyEvent a, SafetyEvent b) {
    final severity = safetyEventPriority(a).compareTo(safetyEventPriority(b));
    if (severity != 0) return severity;
    return safetyEventTime(b).compareTo(safetyEventTime(a));
  }

  List<WidgetBuilder> _sectionEntries({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<SafetyEvent> events,
  }) {
    if (events.isEmpty) return const <WidgetBuilder>[];

    final entries = <WidgetBuilder>[
      (context) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, size: 23),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  '${events.length}',
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 9),
          ],
        ),
      ),
    ];

    for (final event in events) {
      entries.add(
        (context) => SafetyEventCard(
          key: ValueKey('alert-card-${event.id}'),
          event: event,
          onTap: () => widget.onOpenEvent(event),
        ),
      );
    }
    return entries;
  }

  Future<void> _openSearch() async {
    final controller = TextEditingController(text: query);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Szukaj w alertach'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Tytuł, opis albo źródło',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
          onSubmitted: (text) => Navigator.pop(dialogContext, text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Szukaj'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && mounted) {
      setState(() => query = value.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayEvents = deduplicateSafetyEventsForDisplay(widget.events);
    final matched = displayEvents.where(_matchesTextAndCategory).toList();
    final active = matched.where(safetyEventIsActive).toList()
      ..sort(_sortEvents);
    final ended = matched.where(safetyEventIsHistorical).toList()
      ..sort(_sortEvents);
    final other =
        matched
            .where(
              (event) =>
                  !safetyEventIsActive(event) &&
                  !safetyEventIsHistorical(event),
            )
            .toList()
          ..sort(_sortEvents);

    final critical = active
        .where(
          (event) => safetyVisualLevel(event) == SafetyVisualLevel.critical,
        )
        .toList();
    final high = active
        .where((event) => safetyVisualLevel(event) == SafetyVisualLevel.high)
        .toList();
    final remaining = active
        .where(
          (event) => !{
            SafetyVisualLevel.critical,
            SafetyVisualLevel.high,
          }.contains(safetyVisualLevel(event)),
        )
        .toList();

    final visibleCount = switch (lifecycle) {
      'Aktywne' => active.length,
      'Zakończone' => ended.length,
      _ => matched.length,
    };

    final entries = <WidgetBuilder>[
      (context) => Row(
        children: [
          Expanded(
            child: Text(
              'Alerty',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (critical.isNotEmpty)
            Semantics(
              label: '${critical.length} krytycznych aktywnych alertów',
              child: Chip(
                avatar: const Icon(Icons.report_rounded, size: 18),
                label: Text('${critical.length} KRYTYCZNE'),
              ),
            ),
        ],
      ),
      (context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'Najpoważniejsze aktywne zagrożenia są zawsze na górze.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
      (context) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Card(
          elevation: 0,
          child: ExpansionTile(
            leading: const Icon(Icons.tune_rounded),
            title: const Text('Filtry i wyszukiwanie'),
            subtitle: Text(
              lifecycle == 'Aktywne' &&
                      category == 'Wszystkie' &&
                      query.isEmpty
                  ? 'Domyślnie: aktywne alerty'
                  : '$lifecycle • $category${query.isEmpty ? '' : ' • wyszukiwanie'}',
            ),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ['Aktywne', 'Wszystkie', 'Zakończone']
                      .map(
                        (value) => ChoiceChip(
                          label: Text(value),
                          selected: lifecycle == value,
                          onSelected: (_) =>
                              setState(() => lifecycle = value),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 9),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      [
                            'Wszystkie',
                            'Pogoda',
                            'Bezpieczeństwo',
                            'Cyber',
                            'Granica',
                            'Inne',
                          ]
                          .map(
                            (value) => FilterChip(
                              label: Text(value),
                              selected: category == value,
                              onSelected: (_) =>
                                  setState(() => category = value),
                            ),
                          )
                          .toList(),
                ),
              ),
              const SizedBox(height: 11),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _openSearch,
                      icon: const Icon(Icons.search),
                      label: Text(
                        query.isEmpty
                            ? 'Szukaj w alertach'
                            : 'Szukaj: $query',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (query.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Wyczyść wyszukiwanie',
                      onPressed: () => setState(() => query = ''),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
      (context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '$visibleCount komunikatów w wybranym widoku',
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ),
    ];

    if (visibleCount == 0) {
      entries.add(
        (context) => const Padding(
          padding: EdgeInsets.only(top: 14),
          child: Card(
            child: ListTile(
              leading: Icon(Icons.notifications_none_outlined),
              title: Text('Brak alertów dla wybranego widoku'),
              subtitle: Text('Zmień filtry albo wyszukiwane hasło.'),
            ),
          ),
        ),
      );
    }

    if (lifecycle != 'Zakończone') {
      entries
        ..addAll(
          _sectionEntries(
            title: 'Krytyczne',
            subtitle: 'Bezpośrednie zagrożenia wymagające najwyższej uwagi.',
            icon: Icons.report_rounded,
            events: critical,
          ),
        )
        ..addAll(
          _sectionEntries(
            title: 'Wysokie',
            subtitle: 'Poważne aktywne ostrzeżenia.',
            icon: Icons.warning_amber_rounded,
            events: high,
          ),
        )
        ..addAll(
          _sectionEntries(
            title: 'Pozostałe aktywne',
            subtitle: 'Ostrzeżenia i informacje o niższym priorytecie.',
            icon: Icons.notifications_active_outlined,
            events: remaining,
          ),
        );
    }

    if (lifecycle == 'Wszystkie') {
      entries.addAll(
        _sectionEntries(
          title: 'Inne komunikaty',
          subtitle: 'Zaplanowane lub o nieustalonej ważności.',
          icon: Icons.schedule_outlined,
          events: other,
        ),
      );
    }

    if (lifecycle != 'Aktywne') {
      entries.addAll(
        _sectionEntries(
          title: 'Zakończone i historyczne',
          subtitle: 'Wyciszone komunikaty, które nie są już aktywne.',
          icon: Icons.history_rounded,
          events: ended,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView.builder(
        key: const PageStorageKey('alerts'),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 26),
        itemCount: entries.length,
        itemBuilder: (context, index) => entries[index](context),
      ),
    );
  }
}
