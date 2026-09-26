import 'package:flutter/material.dart';

import '../model.dart';
import '../ui/safety_event_card.dart';

const _multiRegionKey = '__MULTI_REGION__';
const _otherRegionKey = '__OTHER_REGION__';

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

class _AlertDisplayItem {
  final SafetyEvent event;
  final int groupedCount;
  final List<String> areas;

  const _AlertDisplayItem({
    required this.event,
    required this.groupedCount,
    required this.areas,
  });
}

class _AlertRegionSection {
  final String key;
  final String title;
  final String subtitle;
  final List<_AlertDisplayItem> items;

  const _AlertRegionSection({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.items,
  });
}

List<String> alertRegionCodesForDisplay(Iterable<String> rawAreas) {
  final values = <String>{};
  for (final code in rawAreas) {
    if (code == 'PL' || regions.containsKey(code)) values.add(code);
  }
  final result = values.toList()
    ..sort((a, b) {
      if (a == 'PL') return -1;
      if (b == 'PL') return 1;
      return (regions[a] ?? a).compareTo(regions[b] ?? b);
    });
  return result;
}

String alertRegionBucketForDisplay(Iterable<String> rawAreas) {
  final areas = alertRegionCodesForDisplay(rawAreas);
  if (areas.contains('PL')) return 'PL';
  final provinceCodes = areas.where((code) => code != 'PL').toList();
  if (provinceCodes.length == 1) return provinceCodes.single;
  if (provinceCodes.length > 1) return _multiRegionKey;
  return _otherRegionKey;
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

  List<String> _safeAreas(SafetyEvent event) {
    final raw = event.data['regions'];
    if (raw is! List) return const <String>[];
    return alertRegionCodesForDisplay(raw.whereType<String>());
  }

  bool _matchesTextAndCategory(SafetyEvent event) {
    if (category != 'Wszystkie' && _categoryOf(event) != category) {
      return false;
    }
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;

    final areaText = _safeAreas(
      event,
    ).map((code) => regions[code] ?? code).join(' ');
    final text =
        '${event.title} ${event.description} ${safetySourceLabel(event)} $areaText'
            .toLowerCase();
    return text.contains(needle);
  }

  bool _matchesLifecycle(SafetyEvent event) => switch (lifecycle) {
    'Aktywne' => safetyEventIsActive(event),
    'Zakończone' => safetyEventIsHistorical(event),
    _ => true,
  };

  int _sortItems(_AlertDisplayItem a, _AlertDisplayItem b) {
    final severity = safetyEventPriority(
      a.event,
    ).compareTo(safetyEventPriority(b.event));
    if (severity != 0) return severity;
    return safetyEventTime(b.event).compareTo(safetyEventTime(a.event));
  }

  List<_AlertDisplayItem> _displayItems() {
    final filtered = widget.events
        .where(_matchesTextAndCategory)
        .where(_matchesLifecycle)
        .toList();

    final grouped = groupSafetyEventsForDashboard(filtered);
    return grouped
        .map(
          (group) => _AlertDisplayItem(
            event: group.primary,
            groupedCount: group.count,
            areas: alertRegionCodesForDisplay(group.areas),
          ),
        )
        .toList();
  }

  List<_AlertRegionSection> _regionSections(List<_AlertDisplayItem> items) {
    final buckets = <String, List<_AlertDisplayItem>>{};

    for (final item in items) {
      final key = alertRegionBucketForDisplay(item.areas);
      buckets.putIfAbsent(key, () => <_AlertDisplayItem>[]).add(item);
    }
    for (final bucket in buckets.values) {
      bucket.sort(_sortItems);
    }

    final sections = <_AlertRegionSection>[];

    void addSection(String key, String title, String subtitle) {
      final bucket = buckets[key];
      if (bucket == null || bucket.isEmpty) return;
      sections.add(
        _AlertRegionSection(
          key: key,
          title: title,
          subtitle: subtitle,
          items: bucket,
        ),
      );
    }

    addSection(
      'PL',
      'Cała Polska',
      'Komunikaty obowiązujące na poziomie ogólnokrajowym.',
    );

    final provinceKeys =
        buckets.keys
            .where((key) => regions.containsKey(key) && key != 'PL')
            .toList()
          ..sort((a, b) => (regions[a] ?? a).compareTo(regions[b] ?? b));
    for (final key in provinceKeys) {
      addSection(key, regions[key]!, 'Alerty przypisane do tego województwa.');
    }

    addSection(
      _multiRegionKey,
      'Kilka województw',
      'Jeden komunikat obejmuje więcej niż jedno województwo — nie jest powielany na liście.',
    );
    addSection(
      _otherRegionKey,
      'Obszar nieustalony',
      'Źródło nie przypisało komunikatu do konkretnego województwa.',
    );

    return sections;
  }

  List<WidgetBuilder> _sectionEntries(_AlertRegionSection section) {
    final entries = <WidgetBuilder>[
      (context) => Padding(
        key: ValueKey('alert-region-${section.key}'),
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(Icons.location_on_outlined, size: 23),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    section.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    section.subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${section.items.length}',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    ];

    for (final item in section.items) {
      entries.add(
        (context) => SafetyEventCard(
          key: ValueKey('alert-card-${section.key}-${item.event.id}'),
          event: item.event,
          groupedCount: item.groupedCount,
          areaOverride: item.areas,
          onTap: () => widget.onOpenEvent(item.event),
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
            hintText: 'Tytuł, opis, źródło albo województwo',
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
    final items = _displayItems();
    final sections = _regionSections(items);
    final affectedProvinces = <String>{};
    for (final item in items) {
      affectedProvinces.addAll(
        item.areas.where((code) => code != 'PL' && regions.containsKey(code)),
      );
    }
    final affectedProvinceCount = affectedProvinces.length;

    final entries = <WidgetBuilder>[
      (context) => Row(
        children: [
          Expanded(
            child: Text(
              'Alerty',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          IconButton(
            tooltip: 'Szukaj w alertach',
            onPressed: _openSearch,
            icon: const Icon(Icons.search_rounded),
          ),
        ],
      ),
      (context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'Komunikaty są uporządkowane według województw, a nie według sztucznego rankingu ważności.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
      (context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Filtry i wyszukiwanie',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 9),
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
                const SizedBox(height: 9),
                Wrap(
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
                if (query.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.search, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Szukasz: $query',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Wyczyść wyszukiwanie',
                        onPressed: () => setState(() => query = ''),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      (context) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          items.isEmpty
              ? 'Brak komunikatów w wybranym widoku'
              : '${items.length} komunikatów • $affectedProvinceCount województw',
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    ];

    if (items.isEmpty) {
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
    } else {
      for (final section in sections) {
        entries.addAll(_sectionEntries(section));
      }
    }

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView.builder(
        key: const PageStorageKey('alerts-by-region'),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 26),
        itemCount: entries.length,
        itemBuilder: (context, index) => entries[index](context),
      ),
    );
  }
}
