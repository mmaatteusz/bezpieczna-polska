import 'package:flutter/material.dart';

import 'model.dart';

class SecurityLevel {
  final Map<String, dynamic> data;
  SecurityLevel._(this.data);

  factory SecurityLevel.parse(dynamic raw) {
    final m = Map<String, dynamic>.from(raw as Map);
    if (!['ALFA', 'BRAVO', 'CHARLIE', 'DELTA'].contains(m['level']) ||
        !['PHYSICAL', 'CRP'].contains(m['type']) ||
        ![
          'NATIONAL',
          'REGIONAL',
          'INFRASTRUCTURE',
          'EXTRATERRITORIAL_INFRASTRUCTURE',
        ].contains(m['scope']) ||
        m['isActive'] is! bool ||
        m['regions'] is! List) {
      throw const FormatException('Niepoprawny stopień alarmowy');
    }
    for (final key in [
      'id',
      'area',
      'description',
      'issuedBy',
      'sourceUrl',
      'rawSourceId',
      'publishedAt',
    ]) {
      if (m[key] is! String || (m[key] as String).isEmpty) {
        throw const FormatException('Niepełny stopień alarmowy');
      }
    }
    final source = Uri.parse(m['sourceUrl'] as String);
    if (source.scheme != 'https' ||
        source.host != 'www.gov.pl' ||
        !source.path.startsWith('/web/rcb/') ||
        source.userInfo.isNotEmpty) {
      throw const FormatException('Niepoprawne źródło stopnia');
    }
    final start = DateTime.parse(m['validFrom'] as String);
    final end = DateTime.parse(m['validTo'] as String);
    if (!end.isAfter(start)) {
      throw const FormatException('Niepoprawny termin');
    }
    return SecurityLevel._(m);
  }

  String get level => data['level'] as String;
  String get type => data['type'] as String;
  String get scope => data['scope'] as String;
  String get area => data['area'] as String;
  String get sourceUrl => data['sourceUrl'] as String;
  String get label => '${level}${type == 'CRP' ? '-CRP' : ''}';

  String get scopeLabel => switch (scope) {
    'NATIONAL' => 'Cała Polska',
    'REGIONAL' => 'Zakres regionalny',
    'INFRASTRUCTURE' => 'Wybrana infrastruktura',
    'EXTRATERRITORIAL_INFRASTRUCTURE' =>
      'Polska infrastruktura poza granicami kraju',
    _ => 'Zakres szczególny',
  };

  bool validAt(DateTime now) =>
      !now.isBefore(DateTime.parse(data['validFrom'] as String)) &&
      !now.isAfter(DateTime.parse(data['validTo'] as String));
}

List<SecurityLevel> securityLevelsFromSnapshot(
  Snapshot? snapshot, {
  bool national = false,
}) {
  final data = snapshot?.data;
  if (data == null) return const <SecurityLevel>[];
  final raw = national
      ? (data['nationalSecurityLevels'] as List? ??
            data['securityLevels'] as List? ??
            const [])
      : (data['securityLevels'] as List? ?? const []);
  return raw.map(SecurityLevel.parse).toList(growable: false);
}

bool levelsFresh(Map<String, dynamic>? data, bool online, DateTime now) {
  if (!online || data == null || data['securityLevelsStatus'] != 'AVAILABLE') {
    return false;
  }
  final sources = data['sources'] as List? ?? [];
  for (final raw in sources) {
    final h = raw as Map;
    if (h['id'] != 'LEVELS') continue;
    final last = DateTime.tryParse(h['lastSuccess'] as String? ?? '');
    return h['state'] == 'HEALTHY' &&
        last != null &&
        !last.isAfter(now.add(const Duration(seconds: 30))) &&
        now.difference(last).inSeconds < (h['maxAgeSeconds'] as num);
  }
  return false;
}

class SecurityLevelsSummaryCard extends StatelessWidget {
  final Snapshot? snapshot;
  final bool online;
  final VoidCallback onTap;
  final DateTime? now;

  const SecurityLevelsSummaryCard({
    super.key,
    required this.snapshot,
    required this.online,
    required this.onTap,
    this.now,
  });

  @override
  Widget build(BuildContext context) {
    final time = now ?? DateTime.now();
    final data = snapshot?.data;
    final fresh = levelsFresh(data, online, time);
    final items = securityLevelsFromSnapshot(
      snapshot,
      national: true,
    ).where((item) => item.validAt(time)).toList(growable: false);
    final nationwide = items
        .where((item) => item.scope == 'NATIONAL')
        .toList(growable: false);
    final scoped = items
        .where((item) => item.scope != 'NATIONAL')
        .toList(growable: false);
    final nationwideLabels =
        nationwide.map((item) => item.label).toSet().toList()..sort();

    final title = !fresh
        ? items.isEmpty
              ? 'Brak świeżych danych o stopniach'
              : 'Ostatnio zapisane stopnie alarmowe'
        : nationwideLabels.isEmpty
        ? 'Aktywne stopnie o szczególnym zakresie'
        : nationwideLabels.join(' • ');

    final detail = !fresh
        ? 'Otwórz szczegóły, aby sprawdzić ostatni zapis i czas aktualizacji.'
        : scoped.isEmpty
        ? 'Obowiązują na wskazanym obszarze. To poziom gotowości służb i administracji.'
        : '${scoped.length} ${scoped.length == 1 ? 'dodatkowy stopień dotyczy' : 'dodatkowe stopnie dotyczą'} wybranej infrastruktury lub szczególnego obszaru.';

    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.security_rounded,
                  color: scheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Stopnie alarmowe',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      detail,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                    if (fresh) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Dane RCB • ${stamp(data?['securityLevelsLastSuccess'])}',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
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

class SecurityLevelsScreen extends StatelessWidget {
  final Snapshot? snapshot;
  final bool online;
  final void Function(String) openSource;

  const SecurityLevelsScreen({
    super.key,
    required this.snapshot,
    required this.online,
    required this.openSource,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Stopnie alarmowe')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        SecurityLevelsPanel(
          snapshot: snapshot,
          online: online,
          openSource: openSource,
          includeNationalContext: true,
        ),
      ],
    ),
  );
}

class SecurityLevelsPanel extends StatelessWidget {
  final Snapshot? snapshot;
  final bool online;
  final void Function(String) openSource;
  final DateTime? now;
  final bool includeNationalContext;

  const SecurityLevelsPanel({
    super.key,
    required this.snapshot,
    required this.online,
    required this.openSource,
    this.now,
    this.includeNationalContext = false,
  });

  @override
  Widget build(BuildContext context) {
    final time = now ?? DateTime.now();
    final data = snapshot?.data;
    final fresh = levelsFresh(data, online, time);
    final items = securityLevelsFromSnapshot(
      snapshot,
      national: includeNationalContext,
    );

    final groups = <String, List<SecurityLevel>>{
      'NATIONAL': [],
      'REGIONAL': [],
      'INFRASTRUCTURE': [],
      'EXTRATERRITORIAL_INFRASTRUCTURE': [],
    };
    for (final item in items) {
      groups[item.scope]!.add(item);
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stopnie alarmowe RP',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text(
              'To poziomy gotowości służb, administracji i chronionych systemów. Sam stopień nie oznacza bezpośredniego zagrożenia dla mieszkańca.',
            ),
            const SizedBox(height: 12),
            _FreshnessBanner(
              fresh: fresh,
              hasItems: items.isNotEmpty,
              lastSuccess: data?['securityLevelsLastSuccess'],
            ),
            if (items.isEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                'Brak wpisów nie potwierdza braku obowiązujących stopni. Sprawdź oficjalne komunikaty RCB, jeśli dane nie są świeże.',
              ),
            ] else ...[
              for (final entry in groups.entries)
                if (entry.value.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    _groupTitle(entry.key),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final item in entry.value)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _SecurityLevelTile(
                        item: item,
                        now: time,
                        openSource: openSource,
                      ),
                    ),
                ],
            ],
            const SizedBox(height: 6),
            Text(
              'Źródło: Rządowe Centrum Bezpieczeństwa. Aplikacja pokazuje opublikowane decyzje i ich zakres; nie interpretuje stopnia jako osobnego alertu dla ludności.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _groupTitle(String scope) => switch (scope) {
    'NATIONAL' => 'Cała Polska',
    'REGIONAL' => 'Zakres regionalny',
    'INFRASTRUCTURE' => 'Wybrana infrastruktura',
    'EXTRATERRITORIAL_INFRASTRUCTURE' =>
      'Polska infrastruktura poza granicami kraju',
    _ => 'Pozostałe',
  };
}

class _FreshnessBanner extends StatelessWidget {
  final bool fresh;
  final bool hasItems;
  final dynamic lastSuccess;

  const _FreshnessBanner({
    required this.fresh,
    required this.hasItems,
    required this.lastSuccess,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = fresh
        ? 'Dane aktualne z RCB'
        : hasItems
        ? 'Ostatnie zapisane dane'
        : 'Brak potwierdzonych aktualnych danych';
    final detail =
        'Aktualność: ${stamp(lastSuccess)}${fresh ? '' : ' — niepotwierdzona'}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fresh
            ? scheme.primaryContainer.withAlpha(110)
            : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: fresh ? scheme.primary.withAlpha(55) : scheme.outlineVariant,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            fresh ? Icons.cloud_done_outlined : Icons.history_rounded,
            size: 21,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SecurityLevelTile extends StatelessWidget {
  final SecurityLevel item;
  final DateTime now;
  final void Function(String) openSource;

  const _SecurityLevelTile({
    required this.item,
    required this.now,
    required this.openSource,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = item.validAt(now);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: item.type == 'CRP'
                      ? scheme.secondaryContainer
                      : scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  item.label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: item.type == 'CRP'
                        ? scheme.onSecondaryContainer
                        : scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                item.scopeLabel,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            item.area,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (item.type == 'CRP') ...[
            const SizedBox(height: 5),
            const Text(
              'Dotyczy cyberprzestrzeni i systemów teleinformatycznych.',
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Od: ${stamp(item.data['validFrom'])}\nObowiązuje do: ${stamp(item.data['validTo'])}',
          ),
          if (!active) ...[
            const SizedBox(height: 6),
            Text(
              'Zapisany termin nie obejmuje bieżącej chwili.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 5),
          TextButton.icon(
            onPressed: () => openSource(item.sourceUrl),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Otwórz oficjalne źródło'),
          ),
        ],
      ),
    );
  }
}
