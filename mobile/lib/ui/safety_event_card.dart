import 'package:flutter/material.dart';

import '../model.dart';

enum SafetyVisualLevel { critical, high, warning, information, historical }

String safetySourceLabel(SafetyEvent event) {
  final sources = event.sources;
  if (sources.isEmpty) return 'Źródło oficjalne';

  final ids = sources.map((source) => source['id']?.toString()).toSet();
  final hasRso = ids.contains('RSO');
  final hasWczk = ids.any((id) => id != null && id.startsWith('WCZK-'));
  if (hasRso && hasWczk) return 'WCZK / RSO • ten sam komunikat';
  if (hasRso && event.areas.isNotEmpty && !event.areas.contains('PL')) {
    return 'WCZK • przez RSO';
  }

  final name = sources.first['name']?.toString().trim() ?? '';
  return name.isEmpty ? 'Źródło oficjalne' : name;
}

int independentSourceCount(SafetyEvent event) {
  final incident = event.data['_incident'];
  if (incident is Map && incident['sourceCount'] is int) {
    return incident['sourceCount'] as int;
  }
  final families = <String>{};
  for (final source in event.sources) {
    final id = source['id']?.toString() ?? '';
    families.add(id == 'RSO' || id.startsWith('WCZK-') ? 'WCZK_RSO' : id);
  }
  return families.length;
}

bool safetyEventIsHistorical(SafetyEvent event, [DateTime? at]) {
  final now = at ?? DateTime.now();
  final lifecycle = event.data['lifecycle']?.toString();
  final end = DateTime.tryParse(event.data['validTo']?.toString() ?? '');
  return event.data['verification'] == 'REFUTED' ||
      const {'ENDED', 'CANCELLED', 'EXPIRED'}.contains(lifecycle) ||
      (end != null && !end.isAfter(now));
}

bool safetyEventIsActive(SafetyEvent event, [DateTime? at]) {
  final now = at ?? DateTime.now();
  return event.data['lifecycle'] == 'ACTIVE' &&
      event.data['messageContext'] == 'ACTUAL' &&
      !safetyEventIsHistorical(event, now);
}

SafetyVisualLevel safetyVisualLevel(SafetyEvent event, [DateTime? at]) {
  if (safetyEventIsHistorical(event, at)) return SafetyVisualLevel.historical;
  return switch (event.data['severity']?.toString()) {
    'CRITICAL' => SafetyVisualLevel.critical,
    'HIGH' || 'SEVERE' => SafetyVisualLevel.high,
    'ELEVATED' || 'MODERATE' => SafetyVisualLevel.warning,
    _ when event.data['officialWarning'] == true => SafetyVisualLevel.warning,
    _ => SafetyVisualLevel.information,
  };
}

int safetyEventPriority(SafetyEvent event, [DateTime? at]) =>
    safetyVisualLevel(event, at).index;

DateTime safetyEventTime(SafetyEvent event) {
  for (final key in ['validFrom', 'publishedAt', 'retrievedAt']) {
    final parsed = DateTime.tryParse(event.data[key]?.toString() ?? '');
    if (parsed != null) return parsed;
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}

bool safetyEventIsSignificant(SafetyEvent event, [DateTime? at]) {
  if (!safetyEventIsActive(event, at)) return false;
  return safetyVisualLevel(event, at) != SafetyVisualLevel.information;
}

String _normalizedEventText(Object? value) => (value?.toString() ?? '')
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String safetyEventDisplayKey(SafetyEvent event) {
  final sortedAreas = [...event.areas]..sort();
  return [
    _normalizedEventText(event.title),
    _normalizedEventText(event.description),
    sortedAreas.join(','),
    event.data['messageContext']?.toString() ?? '',
    event.data['severity']?.toString() ?? '',
    event.data['validFrom']?.toString() ?? '',
    event.data['validTo']?.toString() ?? '',
  ].join('|');
}

List<SafetyEvent> deduplicateSafetyEventsForDisplay(
  Iterable<SafetyEvent> events,
) {
  final seenRecords = <String>{};
  final seenSemantic = <String>{};
  final result = <SafetyEvent>[];

  for (final event in events) {
    final recordKey = event.incidentId?.isNotEmpty == true
        ? 'incident:${event.incidentId}'
        : 'event:${event.id}';
    if (!seenRecords.add(recordKey)) continue;
    if (!seenSemantic.add(safetyEventDisplayKey(event))) continue;
    result.add(event);
  }

  return result;
}

class SafetyEventDisplayGroup {
  final SafetyEvent primary;
  final List<SafetyEvent> events;

  const SafetyEventDisplayGroup({required this.primary, required this.events});

  int get count => events.length;

  List<String> get areas {
    final values = <String>{};
    for (final event in events) {
      values.addAll(event.areas);
    }
    final result = values.toList()..sort();
    return result;
  }
}

String? _dashboardGroupingKey(SafetyEvent event) {
  final ids = event.sources
      .map((source) => source['id']?.toString() ?? '')
      .toSet();
  final family = ids.contains('IMGW_HYDRO')
      ? 'IMGW_HYDRO'
      : ids.contains('IMGW_METEO')
      ? 'IMGW_METEO'
      : null;
  if (family == null || event.areas.isEmpty) return null;

  final title = _normalizedEventText(event.title);
  if (title.isEmpty) return null;

  final validity = safetyEventHasOpenEndedValidity(event)
      ? 'OPEN_ENDED'
      : event.data['validTo']?.toString() ?? '';
  return [
    family,
    title,
    event.data['severity']?.toString() ?? '',
    event.data['messageContext']?.toString() ?? '',
    validity,
  ].join('|');
}

bool _areasOverlap(Iterable<String> a, Iterable<String> b) {
  final left = a.toSet();
  return b.any(left.contains);
}

List<SafetyEventDisplayGroup> groupSafetyEventsForDashboard(
  Iterable<SafetyEvent> events,
) {
  final deduplicated = deduplicateSafetyEventsForDisplay(events);
  final groups = <SafetyEventDisplayGroup>[];
  final keys = <String?>[];
  final groupAreas = <Set<String>>[];

  for (final event in deduplicated) {
    final key = _dashboardGroupingKey(event);
    var match = -1;
    if (key != null) {
      for (var i = 0; i < groups.length; i++) {
        if (keys[i] == key && _areasOverlap(groupAreas[i], event.areas)) {
          match = i;
          break;
        }
      }
    }

    if (match < 0) {
      groups.add(SafetyEventDisplayGroup(primary: event, events: [event]));
      keys.add(key);
      groupAreas.add(event.areas.toSet());
      continue;
    }

    final current = groups[match];
    final mergedEvents = [...current.events, event];
    groups[match] = SafetyEventDisplayGroup(
      primary: current.primary,
      events: mergedEvents,
    );
    groupAreas[match].addAll(event.areas);
  }

  return groups;
}

bool safetyEventHasOpenEndedValidity(SafetyEvent event) {
  final raw = event.data['validTo'];
  if (raw is! String || raw.trim().isEmpty) return false;

  final parsed = DateTime.tryParse(raw);
  return parsed != null && parsed.year >= 9000;
}

String safetyEventTimeLabel(SafetyEvent event, [DateTime? at]) {
  final end = event.data['validTo'];
  if (!safetyEventIsHistorical(event, at) && end is String) {
    if (safetyEventHasOpenEndedValidity(event)) {
      return 'Obowiązuje do odwołania';
    }
    return 'Ważne do ${stamp(end)}';
  }
  final published = event.data['publishedAt'] ?? event.data['retrievedAt'];
  return published == null ? 'Czas nieustalony' : stamp(published);
}

({String label, IconData icon, Color accent, Color fill}) safetyEventAppearance(
  BuildContext context,
  SafetyEvent event,
) {
  final scheme = Theme.of(context).colorScheme;
  return switch (safetyVisualLevel(event)) {
    SafetyVisualLevel.critical => (
      label: 'Krytyczne',
      icon: Icons.report_rounded,
      accent: scheme.error,
      fill: scheme.errorContainer,
    ),
    SafetyVisualLevel.high => (
      label: 'Wysokie',
      icon: Icons.warning_amber_rounded,
      accent: scheme.tertiary,
      fill: Color.alphaBlend(
        scheme.tertiary.withValues(alpha: 0.07),
        scheme.surfaceContainerLowest,
      ),
    ),
    SafetyVisualLevel.warning => (
      label: 'Ostrzeżenie',
      icon: Icons.notification_important_outlined,
      accent: scheme.secondary,
      fill: scheme.surfaceContainerLowest,
    ),
    SafetyVisualLevel.information => (
      label: 'Informacyjne',
      icon: Icons.info_outline_rounded,
      accent: scheme.onSurfaceVariant,
      fill: scheme.surfaceContainerLowest,
    ),
    SafetyVisualLevel.historical => (
      label: 'Zakończone',
      icon: Icons.history_rounded,
      accent: scheme.onSurfaceVariant,
      fill: scheme.surfaceContainerLow,
    ),
  };
}

class SafetyEventCard extends StatelessWidget {
  final SafetyEvent event;
  final VoidCallback onTap;
  final bool compact;
  final int groupedCount;
  final List<String>? areaOverride;

  const SafetyEventCard({
    super.key,
    required this.event,
    required this.onTap,
    this.compact = false,
    this.groupedCount = 1,
    this.areaOverride,
  });

  String get verificationLabel =>
      switch (event.data['verification']?.toString()) {
        'CONFIRMED' => 'POTWIERDZONE',
        'PROBABLE' => 'PRAWDOPODOBNE',
        'UNVERIFIED' => 'NIEZWERYFIKOWANE',
        'REFUTED' => 'ZDEMENTOWANE',
        'DISPUTED' => 'SPRZECZNE',
        _ => 'NIEUSTALONE',
      };

  String get originLabel =>
      event.provenance == 'ŹRÓDŁO OFICJALNE' ? 'OFICJALNE' : event.provenance;

  String _areaLabel() {
    final areas = areaOverride ?? event.areas;
    return areas.isEmpty
        ? 'Obszar nieustalony'
        : areas.map((r) => regions[r] ?? r).join(', ');
  }

  Widget _metadata(BuildContext context, IconData icon, String value) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }

  Widget _buildCard(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final visual = safetyEventAppearance(context, event);
    final sourceCount = independentSourceCount(event);
    final instruction = safetyEventIsSignificant(event)
        ? event.instructions.firstOrNull
        : null;
    final labels = [
      originLabel,
      verificationLabel,
      event.badge,
      if (groupedCount > 1) 'Komunikaty w grupie: $groupedCount',
      if (sourceCount > 1) 'Niezależne źródła: $sourceCount',
      if (event.hasConflictingReports) 'Różnice w komunikatach',
    ];

    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(visual.icon, size: 19, color: visual.accent),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        visual.label,
                        style: text.labelLarge?.copyWith(color: visual.accent),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(event.title, style: text.titleLarge),
                const SizedBox(height: 5),
                Text(
                  event.description,
                  maxLines: compact ? 2 : 4,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium,
                ),
                if (instruction != null) ...[
                  const SizedBox(height: 10),
                  _metadata(context, Icons.arrow_forward_rounded, instruction),
                ],
                const SizedBox(height: 12),
                _metadata(context, Icons.place_outlined, _areaLabel()),
                const SizedBox(height: 4),
                _metadata(context, Icons.schedule, safetyEventTimeLabel(event)),
                const SizedBox(height: 4),
                _metadata(
                  context,
                  Icons.feed_outlined,
                  safetySourceLabel(event),
                ),
                const SizedBox(height: 10),
                Text(
                  labels.join(' · '),
                  style: text.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    try {
      return _buildCard(context);
    } catch (error, stackTrace) {
      assert(() {
        debugPrint('SafetyEventCard render failure: $error');
        debugPrintStack(stackTrace: stackTrace);
        return true;
      }());

      final rawTitle = event.data['title']?.toString().trim() ?? '';
      return Card(
        margin: EdgeInsets.only(bottom: compact ? 10 : 12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Nie udało się wyświetlić szczegółów komunikatu',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (rawTitle.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          rawTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 4),
                      const Text('Dotknij, aby spróbować otworzyć szczegóły.'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }
}
