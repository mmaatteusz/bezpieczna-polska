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

bool safetyEventHasOpenEndedValidity(SafetyEvent event) {
  final raw = event.data['validTo'];
  if (raw is! String || raw.trim().isEmpty) return false;

  for (final match in RegExp(r'\d{4,}').allMatches(raw)) {
    final value = int.tryParse(match.group(0)!);
    if (value != null && value >= 9000) return true;
  }

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

class _CardVisual {
  final String label;
  final String hint;
  final IconData icon;
  final Color background;
  final Color foreground;
  final Color accent;
  final double borderWidth;
  final double elevation;
  final double iconSize;

  const _CardVisual({
    required this.label,
    required this.hint,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.accent,
    required this.borderWidth,
    required this.elevation,
    required this.iconSize,
  });
}

class SafetyEventCard extends StatelessWidget {
  final SafetyEvent event;
  final VoidCallback onTap;
  final bool compact;

  const SafetyEventCard({
    super.key,
    required this.event,
    required this.onTap,
    this.compact = false,
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

  _CardVisual _visual(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (safetyVisualLevel(event)) {
      SafetyVisualLevel.critical => _CardVisual(
        label: 'KRYTYCZNE',
        hint: 'BEZPOŚREDNIE ZAGROŻENIE',
        icon: Icons.report_rounded,
        background: scheme.errorContainer,
        foreground: scheme.onErrorContainer,
        accent: scheme.error,
        borderWidth: 3,
        elevation: 3,
        iconSize: 34,
      ),
      SafetyVisualLevel.high => _CardVisual(
        label: 'WYSOKIE',
        hint: 'WAŻNE OSTRZEŻENIE',
        icon: Icons.warning_amber_rounded,
        background: scheme.tertiaryContainer,
        foreground: scheme.onTertiaryContainer,
        accent: scheme.tertiary,
        borderWidth: 2,
        elevation: 2,
        iconSize: 30,
      ),
      SafetyVisualLevel.warning => _CardVisual(
        label: 'OSTRZEŻENIE',
        hint: 'ZACHOWAJ UWAGĘ',
        icon: Icons.notification_important_outlined,
        background: scheme.secondaryContainer,
        foreground: scheme.onSecondaryContainer,
        accent: scheme.secondary,
        borderWidth: 1.5,
        elevation: 1,
        iconSize: 27,
      ),
      SafetyVisualLevel.information => _CardVisual(
        label: 'INFORMACYJNE',
        hint: 'INFORMACJA',
        icon: Icons.info_outline_rounded,
        background: scheme.surfaceContainerLow,
        foreground: scheme.onSurface,
        accent: scheme.outline,
        borderWidth: 1,
        elevation: 0,
        iconSize: 23,
      ),
      SafetyVisualLevel.historical => _CardVisual(
        label: 'ZAKOŃCZONE',
        hint: 'HISTORYCZNE',
        icon: Icons.history_rounded,
        background: scheme.surfaceContainerLowest,
        foreground: scheme.onSurfaceVariant,
        accent: scheme.outlineVariant,
        borderWidth: 1,
        elevation: 0,
        iconSize: 21,
      ),
    };
  }

  String _areaLabel() => event.areas.isEmpty
      ? 'Obszar nieustalony'
      : event.areas.map((r) => regions[r] ?? r).join(', ');

  String _timeLabel() => safetyEventTimeLabel(event);

  String? _firstInstruction() {
    final raw = event.data['instructions'];
    if (raw is! List) return null;
    for (final item in raw) {
      if (item is String && item.trim().isNotEmpty) return item.trim();
    }
    return null;
  }

  Widget _secondaryBadge(BuildContext context, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface.withAlpha(185),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
    ),
  );

  Widget _meta(
    BuildContext context,
    IconData icon,
    String text, {
    int maxLines = 2,
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 17),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          text,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final visual = _visual(context);
    final sourceCount = independentSourceCount(event);
    final level = safetyVisualLevel(event);
    final prominent =
        level == SafetyVisualLevel.critical || level == SafetyVisualLevel.high;
    final instruction = _firstInstruction();

    return Card(
      margin: EdgeInsets.only(bottom: compact ? 10 : 12),
      color: visual.background,
      elevation: visual.elevation,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(prominent ? 20 : 16),
        side: BorderSide(color: visual.accent, width: visual.borderWidth),
      ),
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: visual.accent, width: 6)),
          ),
          padding: EdgeInsets.fromLTRB(
            prominent ? 17 : 14,
            compact ? 13 : 15,
            13,
            compact ? 13 : 15,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    visual.icon,
                    size: visual.iconSize,
                    color: visual.foreground,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          visual.label,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: visual.foreground,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                        ),
                        if (prominent)
                          Text(
                            visual.hint,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: visual.foreground,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: visual.foreground),
                ],
              ),
              SizedBox(height: prominent ? 12 : 9),
              Text(
                event.title,
                style:
                    (prominent
                            ? Theme.of(context).textTheme.titleLarge
                            : Theme.of(context).textTheme.titleMedium)
                        ?.copyWith(
                          color: visual.foreground,
                          fontWeight: prominent
                              ? FontWeight.w900
                              : FontWeight.w700,
                        ),
              ),
              const SizedBox(height: 7),
              Text(
                event.description,
                maxLines: compact ? 2 : (prominent ? 5 : 4),
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: visual.foreground),
              ),
              const SizedBox(height: 11),
              _meta(context, Icons.location_on_outlined, _areaLabel()),
              const SizedBox(height: 5),
              _meta(context, Icons.schedule_outlined, _timeLabel()),
              const SizedBox(height: 5),
              _meta(
                context,
                Icons.verified_outlined,
                safetySourceLabel(event),
                maxLines: 1,
              ),
              if (instruction != null &&
                  level != SafetyVisualLevel.information &&
                  level != SafetyVisualLevel.historical) ...[
                const SizedBox(height: 11),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withAlpha(180),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.directions_outlined, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          instruction,
                          maxLines: compact ? 2 : 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _secondaryBadge(context, originLabel),
                  _secondaryBadge(context, verificationLabel),
                  _secondaryBadge(context, event.badge),
                  if (sourceCount > 1)
                    _secondaryBadge(context, 'NIEZALEŻNE ŹRÓDŁA: $sourceCount'),
                  if (event.hasConflictingReports)
                    _secondaryBadge(context, 'RÓŻNICE W KOMUNIKATACH'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
