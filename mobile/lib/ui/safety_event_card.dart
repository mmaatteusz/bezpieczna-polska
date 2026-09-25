import 'package:flutter/material.dart';

import '../model.dart';

String safetySourceLabel(SafetyEvent event) {
  final ids = event.sources.map((source) => source['id']?.toString()).toSet();
  final hasRso = ids.contains('RSO');
  final hasWczk = ids.any((id) => id != null && id.startsWith('WCZK-'));
  if (hasRso && hasWczk) return 'WCZK / RSO • ten sam komunikat';
  if (hasRso && event.areas.isNotEmpty && !event.areas.contains('PL')) {
    return 'WCZK • przez RSO';
  }
  return event.sources.first['name']?.toString() ?? 'Źródło oficjalne';
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

  String get severityLabel => switch (event.data['severity']?.toString()) {
    'CRITICAL' => 'KRYTYCZNE',
    'HIGH' || 'SEVERE' => 'WYSOKIE',
    'ELEVATED' || 'MODERATE' => 'PODWYŻSZONE',
    'NORMAL' || 'LOW' => 'STANDARDOWE',
    _ => 'NIEUSTALONE',
  };

  Widget _badge(BuildContext context, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(7),
    ),
    child: Text(text, style: Theme.of(context).textTheme.labelSmall),
  );

  @override
  Widget build(BuildContext context) {
    final sourceCount = independentSourceCount(event);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(compact ? 14 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _badge(context, safetySourceLabel(event)),
                  _badge(context, event.badge),
                  if (!compact) _badge(context, verificationLabel),
                  _badge(context, severityLabel),
                  if (sourceCount > 1)
                    _badge(
                      context,
                      'NIEZALEŻNE ŹRÓDŁA: $sourceCount',
                    ),
                  if (event.hasConflictingReports)
                    _badge(context, 'RÓŻNICE W KOMUNIKATACH'),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                event.title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 7),
              Text(
                event.description,
                maxLines: compact ? 2 : 4,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                event.areas.isEmpty
                    ? 'Obszar nieustalony'
                    : event.areas.map((r) => regions[r] ?? r).join(', '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
