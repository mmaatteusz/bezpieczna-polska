import 'package:flutter/material.dart';

import '../model.dart';
import '../offline_packages.dart';
import '../security_levels.dart';
import '../ui/province_outline.dart';
import '../ui/safety_event_card.dart';

// A successful HTTP response does not establish freshness of upstream feeds.
bool dashboardSourcesFresh(Snapshot? snapshot, String region, DateTime now) {
  if (snapshot == null || !snapshot.freshAt(now)) return false;
  final sources = (snapshot.data['sources'] as List).where((raw) {
    final source = raw as Map;
    return source['enabled'] != false &&
        source['sourceClass'] == 'STATUS' &&
        (source['regionId'] == null ||
            region == 'PL' ||
            source['regionId'] == region);
  }).toList();
  return sources.isNotEmpty &&
      sources.every((raw) {
        final source = raw as Map;
        final last = DateTime.tryParse(source['lastSuccess']?.toString() ?? '');
        final maxAge = source['maxAgeSeconds'];
        return (source['healthStatus'] ?? source['state']) == 'HEALTHY' &&
            last != null &&
            maxAge is num &&
            maxAge > 0 &&
            !last.isAfter(now.add(const Duration(seconds: 30))) &&
            now.difference(last).inMilliseconds < maxAge * 1000;
      });
}

bool dashboardAroundFresh(AroundResult? around, DateTime now) {
  if (around == null || around.data['offlineSnapshotTimestamp'] != null) {
    return false;
  }
  final time = DateTime.tryParse(around.data['serverTime']?.toString() ?? '');
  return time != null &&
      !time.isAfter(now.add(const Duration(seconds: 30))) &&
      now.difference(time) < const Duration(minutes: 1);
}

class DashboardScreen extends StatelessWidget {
  final Snapshot? snapshot;
  final List<SafetyEvent> events;
  final AroundResult? localityAround;
  final OfflineRegionPackage? offlinePackage;
  final bool online;
  final bool loading;
  final bool backgroundSync;
  final String region;
  final String? localityLabel;
  final String? error;
  final Future<void> Function() onRefresh;
  final VoidCallback onChooseLocality;
  final VoidCallback onOpenAlerts;
  final VoidCallback? onOpenMap;
  final VoidCallback onOpenSecurityLevels;
  final void Function(SafetyEvent) onOpenEvent;
  final Map<String, int> readRevisions;

  const DashboardScreen({
    super.key,
    required this.snapshot,
    required this.events,
    required this.localityAround,
    required this.offlinePackage,
    required this.online,
    required this.loading,
    required this.backgroundSync,
    required this.region,
    required this.localityLabel,
    required this.error,
    required this.onRefresh,
    required this.onChooseLocality,
    required this.onOpenAlerts,
    this.onOpenMap,
    required this.onOpenSecurityLevels,
    required this.onOpenEvent,
    this.readRevisions = const {},
  });

  String _freshnessLabel(DateTime now) {
    if (loading || backgroundSync) return 'Aktualizacja…';
    if (!online) return offlinePackage != null ? 'Tryb offline' : 'Brak sieci';
    if (snapshot == null) return 'Łączenie…';
    if (!dashboardSourcesFresh(snapshot, region, now)) {
      return 'Ograniczone dane źródeł';
    }
    if (localityLabel != null && !dashboardAroundFresh(localityAround, now)) {
      return 'Brak świeżych danych okolicy';
    }
    return 'Źródła ostrzeżeń aktualne';
  }

  Widget _alertSummary(
    BuildContext context,
    SafetyEventDisplayGroup group,
    DateTime now,
  ) {
    final event = group.primary;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final visual = safetyEventAppearance(context, event);
    final news = safetyEventNews(event, readRevisions, now);
    final instruction = event.instructions.firstOrNull;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: visual.fill,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: group.count > 1 ? onOpenAlerts : () => onOpenEvent(event),
        child: Ink(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: visual.accent, width: 3)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 11, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [
                          if (news != null) news.label,
                          visual.label,
                          safetySourceLabel(event),
                        ].join(' · '),
                        style: text.labelMedium?.copyWith(color: visual.accent),
                      ),
                      const SizedBox(height: 4),
                      Text(event.title, style: text.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        safetyEventTimeLabel(event),
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (instruction != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          instruction,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (group.count > 1)
                        Text(
                          'Komunikaty w grupie: ${group.count}',
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final national = snapshot?.data['nationalStatus'];
    final nationalFresh =
        online && (snapshot?.freshAt(now, national: true) ?? false);
    final localFresh = online && dashboardAroundFresh(localityAround, now);
    final hasLocality = localityLabel != null;
    final selectedEvents = hasLocality
        ? [
            ...?localityAround?.nearbyEvents.map((item) => item.event),
            ...?localityAround?.regionalEvents,
          ]
        : events;
    final activeEvents =
        deduplicateSafetyEventsForDisplay(
          selectedEvents.where((event) => safetyEventIsSignificant(event, now)),
        )..sort((a, b) {
          final severity = safetyEventPriority(
            a,
            now,
          ).compareTo(safetyEventPriority(b, now));
          if (severity != 0) return severity;
          return safetyEventTime(b).compareTo(safetyEventTime(a));
        });
    final active = groupSafetyEventsForDashboard(activeEvents);
    final local = {
      'hazardLevel': activeEvents.isEmpty
          ? 'NO_LOCAL_REPORTS'
          : activeEvents.any((e) => e.data['severity'] == 'CRITICAL')
          ? 'ACTIVE_DANGER'
          : 'CAUTION',
      'displayText': activeEvents.isEmpty
          ? 'W dostępnych danych nie ma istotnych zdarzeń w tym zakresie.'
          : 'Aktywne komunikaty: ${active.length}',
    };
    final snapshotTime = stamp(snapshot?.data['serverTime']);
    final urgentNational =
        nationalFresh &&
        national is Map &&
        national['hazardLevel'] == 'ACTIVE_DANGER';

    BuildContext? threatsSectionContext;
    void scrollToThreats() {
      final target = threatsSectionContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 300),
        alignment: 0.06,
      );
    }

    Widget nationalStatus() => Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: _StatusBand(
        scope: 'Polska',
        status: national,
        fresh: nationalFresh,
        saved: !online && offlinePackage != null,
        onTap: onOpenAlerts,
      ),
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            key: const PageStorageKey('dashboard'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Sytuacja teraz', style: text.titleLarge),
                  ),
                  IconButton(
                    tooltip: 'Odśwież dane',
                    onPressed: loading || backgroundSync ? null : onRefresh,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _LocalityHeader(
                      locality: localityLabel,
                      region: region,
                      onChoose: onChooseLocality,
                      onStatus: hasLocality ? scrollToThreats : null,
                    ),
                    if (hasLocality)
                      _StatusBand(
                        status: local,
                        fresh: localFresh,
                        saved: false,
                        onTap: scrollToThreats,
                      ),
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(15, 10, 15, 11),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            online ? Icons.schedule : Icons.cloud_off_outlined,
                            size: 18,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _freshnessLabel(now),
                                  style: text.labelLarge,
                                ),
                                if (snapshotTime != 'Nie podano')
                                  Text(
                                    'Ostatni odczyt · $snapshotTime',
                                    style: text.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (!online && offlinePackage != null) ...[
                const SizedBox(height: 10),
                const _InfoBanner(
                  icon: Icons.offline_pin_outlined,
                  text:
                      'Wyświetlamy ostatnie zapisane dane. Mogły pojawić się nowsze ostrzeżenia.',
                ),
              ] else if (error != null) ...[
                const SizedBox(height: 10),
                const _InfoBanner(
                  icon: Icons.cloud_off_outlined,
                  text:
                      'Nie udało się odświeżyć danych. Użyj przycisku odświeżania lub przeciągnij ekran w dół.',
                ),
              ],
              if (urgentNational) ...[
                const SizedBox(height: 12),
                nationalStatus(),
              ],
              if (hasLocality) ...[
                const SizedBox(height: 20),
                Builder(
                  builder: (sectionContext) {
                    threatsSectionContext = sectionContext;
                    return Text('Istotne zagrożenia', style: text.titleLarge);
                  },
                ),
                const SizedBox(height: 10),
                if (active.isNotEmpty)
                  ...active
                      .take(3)
                      .map((group) => _alertSummary(context, group, now))
                else
                  _InfoBanner(
                    icon: localFresh
                        ? Icons.notifications_none_rounded
                        : Icons.location_searching,
                    text: localFresh
                        ? 'Brak istotnych aktywnych komunikatów w tym zakresie.'
                        : loading
                        ? 'Sprawdzamy okolicę.'
                        : 'Brak bieżącej oceny okolicy.',
                  ),
                if (active.length > 3)
                  TextButton(
                    onPressed: onOpenAlerts,
                    child: Text('Zobacz wszystkie (${active.length})'),
                  ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (onOpenMap != null)
                    OutlinedButton.icon(
                      onPressed: onOpenMap,
                      icon: const Icon(Icons.map_outlined, size: 19),
                      label: const Text('Otwórz mapę'),
                    ),
                  OutlinedButton.icon(
                    onPressed: onOpenAlerts,
                    icon: const Icon(
                      Icons.notifications_none_rounded,
                      size: 19,
                    ),
                    label: const Text('Wszystkie alerty'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(),
              ExpansionTile(
                key: const PageStorageKey('dashboard-national'),
                tilePadding: EdgeInsets.zero,
                leading: const Icon(Icons.public_outlined),
                title: const Text('Sytuacja w kraju'),
                children: [
                  if (!urgentNational) nationalStatus(),
                  const SizedBox(height: 8),
                  SecurityLevelsSummaryCard(
                    snapshot: snapshot,
                    online: online,
                    onTap: onOpenSecurityLevels,
                  ),
                  const SizedBox(height: 8),
                ],
              ),
              const Divider(),
              ExpansionTile(
                key: const PageStorageKey('dashboard-coverage'),
                tilePadding: EdgeInsets.zero,
                leading: const Icon(Icons.info_outline),
                title: const Text('Zakres i aktualność danych'),
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Sprawdzamy zdarzenia z geometrią w promieniu 20 km oraz komunikaty dla województwa i kraju. Część źródeł nie podaje dokładnego miejsca. Brak komunikatów nie jest gwarancją bezpieczeństwa. Zalecenia znajdziesz w szczegółach alertu.',
                    ),
                  ),
                  if (localityAround != null)
                    Text(
                      'Odczyt okolicy: ${stamp(localityAround!.data['serverTime'])}',
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocalityHeader extends StatelessWidget {
  final String? locality;
  final String region;
  final VoidCallback onChoose;
  final VoidCallback? onStatus;

  const _LocalityHeader({
    required this.locality,
    required this.region,
    required this.onChoose,
    required this.onStatus,
  });

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF183449);
    const muted = Color(0xFFC0D7E3);
    const paper = Color(0xFFFFFAF2);
    final text = Theme.of(context).textTheme;
    final province = locality == null || region == 'PL'
        ? null
        : regions[region];
    return Ink(
      color: ink,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(17, 14, 14, 4),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showMap =
                constraints.maxWidth >= 290 &&
                MediaQuery.textScalerOf(context).scale(14) <= 19;
            return Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: onStatus,
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Twoja okolica',
                                style: text.labelLarge?.copyWith(color: muted),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                locality ?? 'Wybierz miejscowość',
                                style: text.headlineLarge?.copyWith(
                                  color: paper,
                                ),
                              ),
                              if (locality != null) ...[
                                const SizedBox(height: 5),
                                if (province != null)
                                  Text(
                                    province.toLowerCase(),
                                    style: text.bodySmall?.copyWith(
                                      color: muted,
                                    ),
                                  ),
                                Text(
                                  'Promień 20 km',
                                  style: text.bodySmall?.copyWith(color: muted),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: onChoose,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.only(right: 6),
                          foregroundColor: paper,
                          alignment: Alignment.centerLeft,
                          minimumSize: const Size(0, 48),
                        ),
                        icon: const Icon(Icons.place_outlined, size: 18),
                        label: Text(
                          locality == null
                              ? 'Ustaw lokalizację'
                              : 'Zmień miejscowość',
                        ),
                      ),
                    ],
                  ),
                ),
                if (showMap) ...[
                  const SizedBox(width: 8),
                  ProvinceOutline(region: locality == null ? null : region),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatusBand extends StatelessWidget {
  final String? scope;
  final dynamic status;
  final bool fresh;
  final bool saved;
  final VoidCallback onTap;

  const _StatusBand({
    this.scope,
    required this.status,
    required this.fresh,
    required this.saved,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final level = fresh && status is Map ? status['hazardLevel'] : null;
    final (
      String word,
      IconData icon,
      Color fill,
      Color accent,
    ) = switch (level) {
      'ACTIVE_DANGER' => (
        'POWAŻNE ZAGROŻENIE',
        Icons.report_rounded,
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
      'CAUTION' => (
        'OSTRZEŻENIA',
        Icons.warning_amber_rounded,
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      'NO_ACTIVE_WARNINGS' => (
        'BRAK AKTYWNYCH OSTRZEŻEŃ',
        Icons.verified_user_outlined,
        scheme.surfaceContainerLowest,
        scheme.onSurface,
      ),
      'NO_LOCAL_REPORTS' => (
        'BRAK LOKALNYCH KOMUNIKATÓW',
        Icons.notifications_none_rounded,
        scheme.surfaceContainerLowest,
        scheme.onSurface,
      ),
      _ => (
        fresh ? 'BRAK PEWNEJ OCENY' : 'BRAK ŚWIEŻEJ OCENY',
        fresh ? Icons.help_outline_rounded : Icons.cloud_off_outlined,
        scheme.surfaceContainerHigh,
        scheme.onSurface,
      ),
    };
    final sourceDetail = status is Map
        ? status['displayText']?.toString()
        : null;
    final detail = fresh
        ? sourceDetail ?? 'Brak dodatkowych informacji'
        : saved && sourceDetail != null
        ? 'Ostatnia zapisana ocena: $sourceDetail'
        : 'Nie ma wystarczająco świeżych danych, aby ocenić sytuację.';
    return Ink(
      color: fill,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(15, 12, 12, 12),
          child: Row(
            children: [
              Icon(icon, size: 24, color: accent),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (scope != null) ...[
                      Text(
                        scope!,
                        style: text.labelLarge?.copyWith(color: accent),
                      ),
                      const SizedBox(height: 3),
                    ],
                    Text(
                      word,
                      style: text.titleSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: text.bodySmall?.copyWith(color: accent),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoBanner({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
