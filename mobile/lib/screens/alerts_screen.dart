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
  final String? subtitle;
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
  final _search = TextEditingController();
  String get query => _search.text;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

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

    void addSection(String key, String title, [String? subtitle]) {
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

    addSection('PL', 'Cała Polska');

    final provinceKeys =
        buckets.keys
            .where((key) => regions.containsKey(key) && key != 'PL')
            .toList()
          ..sort((a, b) => (regions[a] ?? a).compareTo(regions[b] ?? b));
    for (final key in provinceKeys) {
      addSection(key, regions[key]!);
    }

    addSection(_multiRegionKey, 'Kilka województw');
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
        padding: const EdgeInsets.only(top: 17, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    section.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${section.items.length}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  semanticsLabel: 'Liczba komunikatów: ${section.items.length}',
                ),
              ],
            ),
            if (section.subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                section.subtitle!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
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

  Widget _filters(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        ExpansionTile(
          key: const PageStorageKey('alert-filters'),
          tilePadding: EdgeInsets.zero,
          leading: const Icon(Icons.tune_rounded, size: 20),
          dense: true,
          title: const Text('Filtry i wyszukiwanie'),
          subtitle: Text(
            [
              lifecycle,
              if (category != 'Wszystkie') category,
              if (query.trim().isNotEmpty) '„${query.trim()}”',
            ].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          shape: const Border(),
          collapsedShape: const Border(),
          childrenPadding: const EdgeInsets.only(bottom: 14),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  key: const PageStorageKey('alerts-search'),
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: 'Szukaj w alertach',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Wyczyść wyszukiwanie',
                            onPressed: () => setState(_search.clear),
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 7,
                  children: [
                    for (final value in const [
                      'Aktywne',
                      'Wszystkie',
                      'Zakończone',
                    ])
                      ChoiceChip(
                        label: Text(value),
                        selected: lifecycle == value,
                        showCheckmark: false,
                        selectedColor: theme.colorScheme.primaryContainer,
                        onSelected: (_) => setState(() => lifecycle = value),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 8),
                Text('Kategoria', style: theme.textTheme.labelLarge),
                Wrap(
                  spacing: 7,
                  children: [
                    for (final value in const [
                      'Wszystkie',
                      'Pogoda',
                      'Bezpieczeństwo',
                      'Cyber',
                      'Granica',
                      'Inne',
                    ])
                      FilterChip(
                        label: Text(value),
                        selected: category == value,
                        onSelected: (_) => setState(() => category = value),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
        const Divider(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _displayItems();
    final sections = _regionSections(items);
    final theme = Theme.of(context);
    final affectedProvinces = {
      for (final item in items)
        ...item.areas.where(
          (code) => code != 'PL' && regions.containsKey(code),
        ),
    };

    final entries = <WidgetBuilder>[
      _filters,
      if (items.isNotEmpty)
        (context) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 12),
          child: Text(
            'Komunikaty: ${items.length}'
            '${affectedProvinces.isEmpty ? '' : ' · Województwa: ${affectedProvinces.length}'}',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
    ];

    if (items.isEmpty) {
      entries.add(
        (context) => const Padding(
          padding: EdgeInsets.only(top: 14),
          child: Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              leading: Icon(Icons.notifications_none_rounded),
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

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: RefreshIndicator(
          onRefresh: widget.onRefresh,
          child: ListView.builder(
            key: const PageStorageKey('alerts-by-region'),
            physics: const AlwaysScrollableScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            itemCount: entries.length,
            itemBuilder: (context, index) => entries[index](context),
          ),
        ),
      ),
    );
  }
}
