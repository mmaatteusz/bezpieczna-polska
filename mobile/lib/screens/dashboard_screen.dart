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

  String _statusWord(dynamic status, bool fresh) {
    if (!fresh) return 'BRAK ŚWIEŻEJ OCENY';
    final level = status is Map ? status['hazardLevel']?.toString() : null;
    return switch (level) {
      'ACTIVE_DANGER' => 'POWAŻNE ZAGROŻENIE',
      'CAUTION' => 'OSTRZEŻENIA',
      'NO_ACTIVE_WARNINGS' => 'BRAK AKTYWNYCH OSTRZEŻEŃ',
      'NO_LOCAL_REPORTS' => 'BRAK LOKALNYCH KOMUNIKATÓW',
      _ => 'BRAK PEWNEJ OCENY',
    };
  }

  String _statusDetail(dynamic status, bool fresh) {
    final text = status is Map ? status['displayText']?.toString() : null;
    if (fresh) return text ?? 'Brak dodatkowych informacji';
    if (!online && offlinePackage != null && text != null) {
      return 'Ostatnia zapisana ocena: $text';
    }
    return 'Nie ma wystarczająco świeżych danych, aby ocenić sytuację.';
  }

  IconData _statusIcon(dynamic status, bool fresh) {
    if (!fresh) return Icons.cloud_off_outlined;
    final level = status is Map ? status['hazardLevel']?.toString() : null;
    return switch (level) {
      'ACTIVE_DANGER' => Icons.report_rounded,
      'CAUTION' => Icons.warning_amber_rounded,
      'NO_ACTIVE_WARNINGS' => Icons.verified_user_rounded,
      _ => Icons.help_outline_rounded,
    };
  }

  Color _statusBackground(BuildContext context, dynamic status, bool fresh) {
    final scheme = Theme.of(context).colorScheme;
    if (!fresh) return scheme.surfaceContainerHigh;
    final level = status is Map ? status['hazardLevel']?.toString() : null;
    return switch (level) {
      'ACTIVE_DANGER' => scheme.errorContainer,
      'CAUTION' => scheme.tertiaryContainer,
      'NO_ACTIVE_WARNINGS' => scheme.primaryContainer,
      _ => scheme.surfaceContainerHigh,
    };
  }

  Color _statusForeground(BuildContext context, dynamic status, bool fresh) {
    final scheme = Theme.of(context).colorScheme;
    if (!fresh) return scheme.onSurface;
    final level = status is Map ? status['hazardLevel']?.toString() : null;
    return switch (level) {
      'ACTIVE_DANGER' => scheme.onErrorContainer,
      'CAUTION' => scheme.onTertiaryContainer,
      'NO_ACTIVE_WARNINGS' => scheme.onPrimaryContainer,
      _ => scheme.onSurface,
    };
  }

  Color _statusAccent(BuildContext context, dynamic status, bool fresh) {
    final scheme = Theme.of(context).colorScheme;
    if (!fresh) return scheme.outline;
    final level = status is Map ? status['hazardLevel']?.toString() : null;
    return switch (level) {
      'ACTIVE_DANGER' => scheme.error,
      'CAUTION' => scheme.tertiary,
      'NO_ACTIVE_WARNINGS' => scheme.primary,
      _ => scheme.outline,
    };
  }

  Widget _statusCard(
    BuildContext context, {
    required String title,
    String? subtitle,
    required dynamic status,
    required bool fresh,
    required bool prominent,
    VoidCallback? onTap,
    String? footer,
  }) {
    final background = _statusBackground(context, status, fresh);
    final foreground = _statusForeground(context, status, fresh);
    final accent = _statusAccent(context, status, fresh);
    final word = _statusWord(status, fresh);
    final radius = prominent ? 26.0 : 20.0;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
            prominent ? 20 : 17,
            prominent ? 19 : 16,
            prominent ? 18 : 16,
            prominent ? 19 : 16,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: accent.withAlpha(prominent ? 125 : 80),
              width: prominent ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: prominent ? 48 : 40,
                    height: prominent ? 48 : 40,
                    decoration: BoxDecoration(
                      color: foreground.withAlpha(18),
                      borderRadius: BorderRadius.circular(prominent ? 16 : 13),
                    ),
                    child: Icon(
                      _statusIcon(status, fresh),
                      size: prominent ? 30 : 24,
                      color: foreground,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: foreground,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: foreground.withAlpha(215),
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (onTap != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 17,
                        color: foreground.withAlpha(190),
                      ),
                    ),
                ],
              ),
              SizedBox(height: prominent ? 17 : 13),
              Text(
                word,
                style:
                    (prominent
                            ? Theme.of(context).textTheme.headlineMedium
                            : Theme.of(context).textTheme.titleLarge)
                        ?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w900,
                          letterSpacing: prominent ? -0.8 : -0.3,
                          height: 1.05,
                        ),
              ),
              const SizedBox(height: 7),
              Text(
                _statusDetail(status, fresh),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: foreground,
                  height: 1.35,
                ),
              ),
              if (footer != null) ...[
                const SizedBox(height: 13),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: foreground.withAlpha(14),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    footer,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _freshnessLabel() {
    if (loading || backgroundSync) return 'Aktualizacja…';
    if (!online) return offlinePackage != null ? 'Tryb offline' : 'Brak sieci';
    if (snapshot == null) return 'Łączenie…';
    if (!dashboardSourcesFresh(snapshot, region, DateTime.now())) {
      return 'Ograniczone dane źródeł';
    }
    if (localityLabel != null &&
        !dashboardAroundFresh(localityAround, DateTime.now())) {
      return 'Brak świeżych danych okolicy';
    }
    return 'Źródła ostrzeżeń aktualne';
  }

  IconData _freshnessIcon() {
    if (loading || backgroundSync) return Icons.sync_rounded;
    if (!online) return Icons.cloud_off_outlined;
    return Icons.cloud_done_outlined;
  }

  String? _snapshotTime() {
    final raw = snapshot?.data['serverTime'];
    if (raw is! String) return null;
    try {
      return stamp(raw);
    } catch (_) {
      return null;
    }
  }

  Widget _freshnessPill(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active =
        online &&
        !loading &&
        !backgroundSync &&
        dashboardSourcesFresh(snapshot, region, DateTime.now()) &&
        (localityLabel == null ||
            dashboardAroundFresh(localityAround, DateTime.now()));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: active
            ? scheme.primaryContainer.withAlpha(150)
            : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active ? scheme.primary.withAlpha(70) : scheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading || backgroundSync)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(_freshnessIcon(), size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              _freshnessLabel(),
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _localitySetupCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onChooseLocality,
        child: Container(
          padding: const EdgeInsets.all(17),
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
                  Icons.add_location_alt_outlined,
                  color: scheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Twoja okolica',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Najpierw spróbujemy ustalić miejscowość z GPS. Jeśli to się nie uda, wpiszesz ją ręcznie.',
                    ),
                    const SizedBox(height: 11),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Ustaw lokalizację',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(width: 5),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 18,
                          color: scheme.primary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(
    BuildContext context, {
    required String title,
    required String subtitle,
    required int count,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.35,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Container(
          constraints: const BoxConstraints(minWidth: 38, minHeight: 34),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: count > 0
                ? scheme.tertiaryContainer
                : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: count > 0
                  ? scheme.onTertiaryContainer
                  : scheme.onSurfaceVariant,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
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
    final local = {
      'hazardLevel': !localFresh
          ? 'UNKNOWN'
          : activeEvents.isEmpty
          ? 'NO_LOCAL_REPORTS'
          : activeEvents.any((e) => e.data['severity'] == 'CRITICAL')
          ? 'ACTIVE_DANGER'
          : 'CAUTION',
      'displayText': activeEvents.isEmpty
          ? 'Nie znaleziono istotnych aktywnych komunikatów w sprawdzanym zakresie. Nie oznacza to braku zagrożeń.'
          : '${active.length} komunikatów lub grup zagrożeń w sprawdzanym zakresie.',
    };
    final snapshotTime = _snapshotTime();

    BuildContext? threatsSectionContext;
    void scrollToThreats() {
      final target = threatsSectionContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        key: const PageStorageKey('dashboard'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sytuacja teraz',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                    ),
                    if (snapshotTime != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Ostatni odczyt: $snapshotTime',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _freshnessPill(context),
            ],
          ),
          const SizedBox(height: 15),
          if (localityLabel == null)
            _localitySetupCard(context)
          else
            _statusCard(
              context,
              title: 'Twoja okolica',
              subtitle:
                  '$localityLabel • promień ${localityAround?.radiusKm.toStringAsFixed(0) ?? '20'} km + komunikaty regionalne',
              status: local,
              fresh: localFresh,
              prominent: true,
              onTap: scrollToThreats,
              footer: localityAround == null
                  ? 'Brak danych lokalnych. Spróbuj odświeżyć.'
                  : !localFresh
                  ? 'Ostatnia zapisana sytuacja • aktualność niepotwierdzona'
                  : 'Komunikaty regionalne mogą dotyczyć całego województwa.',
            ),
          if (!online && offlinePackage != null) ...[
            const SizedBox(height: 10),
            const _InfoBanner(
              icon: Icons.offline_pin_outlined,
              text:
                  'Tryb offline: pokazujemy ostatnie zapisane dane. Mogły pojawić się nowsze ostrzeżenia.',
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 10),
            _InfoBanner(
              icon: Icons.cloud_off_outlined,
              text: 'Nie udało się pobrać świeżych danych. $error',
            ),
          ],
          const SizedBox(height: 25),
          Builder(
            builder: (sectionContext) {
              threatsSectionContext = sectionContext;
              return _sectionHeader(
                sectionContext,
                title: 'Istotne zagrożenia',
                subtitle: localityLabel == null
                    ? 'Wybierz miejscowość, aby zobaczyć komunikaty dla swojej okolicy.'
                    : 'Do trzech najważniejszych komunikatów dla wskazanego zakresu.',
                count: active.length,
              );
            },
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onOpenAlerts,
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('Wszystkie alerty i filtry'),
            ),
          ),
          const SizedBox(height: 3),
          if (localityLabel != null && localityAround == null)
            const _EmptyState(
              icon: Icons.location_searching,
              title: 'Brak oceny lokalnej',
              text:
                  'Nie udało się pobrać danych okolicy. Odśwież ekran; status województwa nie zastępuje danych lokalnych.',
            )
          else if (snapshot == null && offlinePackage == null)
            const _EmptyState(
              icon: Icons.cloud_download_outlined,
              title: 'Pobieramy aktualną sytuację',
              text: 'Możesz przeciągnąć ekran w dół, aby spróbować ponownie.',
            )
          else if (active.isEmpty)
            const _EmptyState(
              icon: Icons.notifications_none_outlined,
              title: 'Brak istotnych aktywnych komunikatów',
              text:
                  'Aplikacja nadal sprawdza źródła. Brak komunikatu nie jest gwarancją bezpieczeństwa.',
            )
          else
            ...active
                .take(3)
                .map(
                  (group) => SafetyEventCard(
                    event: group.primary,
                    compact: true,
                    groupedCount: group.count,
                    areaOverride: group.areas,
                    onTap: group.count > 1
                        ? onOpenAlerts
                        : () => onOpenEvent(group.primary),
                  ),
                ),
          if (active.isNotEmpty) ...[
            const SizedBox(height: 8),
            const _InfoBanner(
              icon: Icons.directions_outlined,
              text:
                  'Co zrobić: przeczytaj zalecenia źródła przy komunikacie. Jeśli ich nie podano, otwórz szczegóły i sprawdź oficjalny komunikat.',
            ),
          ],
          const SizedBox(height: 12),
          _InfoBanner(
            icon: Icons.info_outline,
            text:
                'Zakres danych: zdarzenia z geometrią w promieniu 20 km oraz komunikaty dla województwa i kraju. '
                'Część źródeł nie podaje dokładnego miejsca. Brak komunikatów nie jest gwarancją bezpieczeństwa. '
                '${_freshnessLabel()}${localityAround == null ? '' : ' • Odczyt okolicy: ${stamp(localityAround!.data['serverTime'] as String)}'}.',
          ),
          const SizedBox(height: 16),
          _statusCard(
            context,
            title: 'Polska',
            subtitle: 'Status krajowy • kontekst ogólny',
            status: national,
            fresh: nationalFresh,
            prominent: false,
            onTap: onOpenAlerts,
          ),
          const SizedBox(height: 12),
          SecurityLevelsSummaryCard(
            snapshot: snapshot,
            online: online,
            onTap: onOpenSecurityLevels,
          ),
        ],
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 21, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
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
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 24, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  text,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
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
