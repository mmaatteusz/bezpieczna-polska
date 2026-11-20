import 'package:flutter/material.dart';

import '../model.dart';
import '../offline_packages.dart';
import '../security_levels.dart';
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
  final VoidCallback onOpenSecurityLevels;
  final void Function(SafetyEvent) onOpenEvent;

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
    required this.onOpenSecurityLevels,
    required this.onOpenEvent,
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

  Widget _locationHeader(BuildContext context, DateTime now) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final text = theme.textTheme;
    final locality = localityLabel;
    final province = region == 'PL' ? null : regions[region]?.toLowerCase();
    final serverTime = snapshot?.data['serverTime'];
    final readAt = DateTime.tryParse(serverTime?.toString() ?? '')?.toLocal();
    final syncTime = readAt == null
        ? null
        : DateUtils.isSameDay(readAt, now.toLocal())
        ? MaterialLocalizations.of(context).formatTimeOfDay(
            TimeOfDay.fromDateTime(readAt),
            alwaysUse24HourFormat: true,
          )
        : stamp(serverTime);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Tooltip(
                  message: locality == null
                      ? 'Ustaw lokalizację'
                      : 'Zmień miejscowość',
                  excludeFromSemantics: locality == null,
                  child: InkWell(
                    onTap: onChooseLocality,
                    borderRadius: BorderRadius.circular(4),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              locality ?? 'Ustaw lokalizację',
                              style: text.headlineLarge,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Icon(Icons.expand_more, size: 22, color: muted),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Odśwież dane',
              onPressed: loading || backgroundSync ? null : onRefresh,
              icon: const Icon(Icons.refresh_rounded, size: 22),
            ),
          ],
        ),
        Text(
          locality == null
              ? 'Wybierz miejscowość, żeby zobaczyć lokalne ostrzeżenia.'
              : 'Promień 20 km${province == null ? '' : ' · $province'}',
          style: text.bodyMedium?.copyWith(color: muted),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 6,
          children: [
            Text(
              _freshnessLabel(now),
              style: text.bodySmall?.copyWith(color: muted),
            ),
            if (syncTime != null)
              Text(
                '· Odczyt $syncTime',
                style: text.bodySmall?.copyWith(color: muted),
              ),
          ],
        ),
      ],
    );
  }

  Widget _alertSummary(BuildContext context, SafetyEventDisplayGroup group) {
    final event = group.primary;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final text = theme.textTheme;
    final visual = safetyEventAppearance(context, event);
    final instruction = event.instructions.firstOrNull;
    final place = event.data['locationText']?.toString().trim() ?? '';

    return InkWell(
      onTap: group.count > 1 ? onOpenAlerts : () => onOpenEvent(event),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(visual.icon, size: 19, color: visual.accent),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${safetySourceLabel(event)} · ${visual.label}',
                    style: text.labelMedium?.copyWith(color: visual.accent),
                  ),
                  const SizedBox(height: 5),
                  Text(event.title, style: text.titleLarge),
                  const SizedBox(height: 5),
                  if (place.isNotEmpty)
                    Text(
                      place,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(color: muted),
                    ),
                  Text(
                    safetyEventTimeLabel(event),
                    style: text.bodySmall?.copyWith(color: muted),
                  ),
                  if (instruction != null) ...[
                    const SizedBox(height: 9),
                    Text(
                      instruction,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium,
                    ),
                  ],
                  if (group.count > 1) ...[
                    const SizedBox(height: 5),
                    Text(
                      'Komunikaty w grupie: ${group.count}',
                      style: text.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 9),
            Padding(
              padding: const EdgeInsets.only(top: 25),
              child: Icon(Icons.chevron_right, color: muted, size: 21),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final muted = theme.colorScheme.onSurfaceVariant;
    final national = snapshot?.data['nationalStatus'];
    final nationalFresh =
        online && (snapshot?.freshAt(now, national: true) ?? false);
    final localFresh = online && dashboardAroundFresh(localityAround, now);
    final selectedEvents = localityLabel == null
        ? events
        : [
            ...?localityAround?.nearbyEvents.map((item) => item.event),
            ...?localityAround?.regionalEvents,
          ];
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
    final urgentNational =
        nationalFresh &&
        national is Map &&
        national['hazardLevel'] == 'ACTIVE_DANGER';

    Widget nationalStatus() => _StatusBand(
      status: national,
      fresh: nationalFresh,
      saved: !online && offlinePackage != null,
      onTap: onOpenAlerts,
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            key: const PageStorageKey('dashboard'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 15, 20, 24),
            children: [
              _locationHeader(context, now),
              if (!online && offlinePackage != null) ...[
                const SizedBox(height: 8),
                const Text(
                  'Wyświetlamy ostatnie zapisane dane. Mogły pojawić się nowsze ostrzeżenia.',
                ),
              ] else if (error != null) ...[
                const SizedBox(height: 8),
                const Text('Nie udało się odświeżyć danych.'),
              ],
              if (urgentNational) ...[
                const SizedBox(height: 16),
                nationalStatus(),
              ],
              if (localityLabel != null) ...[
                const SizedBox(height: 26),
                Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          'Ostrzeżenia w okolicy',
                          style: text.titleLarge,
                        ),
                      ),
                    ),
                    if (active.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${active.length}',
                        semanticsLabel: 'Liczba ostrzeżeń: ${active.length}',
                        style: text.labelLarge?.copyWith(color: muted),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(),
                if (active.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    child: Text(
                      localFresh
                          ? 'W dostępnych danych nie ma aktywnych ostrzeżeń dla okolicy.'
                          : loading
                          ? 'Sprawdzamy okolicę.'
                          : 'Brak bieżącej oceny okolicy.',
                      style: text.bodyMedium?.copyWith(color: muted),
                    ),
                  )
                else
                  for (final group in active.take(3)) ...[
                    _alertSummary(context, group),
                    const Divider(),
                  ],
                if (active.length > 3)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: onOpenAlerts,
                      icon: const Icon(Icons.arrow_forward, size: 17),
                      iconAlignment: IconAlignment.end,
                      label: const Text('Wszystkie alerty'),
                    ),
                  ),
              ],
              const SizedBox(height: 18),
              ExpansionTile(
                key: const PageStorageKey('dashboard-national'),
                tilePadding: EdgeInsets.zero,
                dense: true,
                title: Text('Sytuacja w kraju', style: text.titleMedium),
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
                dense: true,
                title: Text(
                  'Zakres i aktualność danych',
                  style: text.titleMedium,
                ),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Sprawdzamy zdarzenia z geometrią w promieniu 20 km oraz komunikaty dla województwa i kraju. Część źródeł nie podaje dokładnego miejsca. Brak komunikatów nie jest gwarancją bezpieczeństwa. Zalecenia znajdziesz w szczegółach alertu.',
                    ),
                  ),
                  if (localityAround != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Odczyt okolicy · ${stamp(localityAround!.data['serverTime'])}',
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBand extends StatelessWidget {
  final dynamic status;
  final bool fresh;
  final bool saved;
  final VoidCallback onTap;

  const _StatusBand({
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
                    Text(
                      'Polska',
                      style: text.labelMedium?.copyWith(color: accent),
                    ),
                    const SizedBox(height: 3),
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
