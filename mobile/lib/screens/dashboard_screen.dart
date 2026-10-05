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
  final VoidCallback? onOpenMap;
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
    this.onOpenMap,
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
                            ? Theme.of(context).textTheme.headlineSmall
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

  String? _snapshotTime() {
    final raw = snapshot?.data['serverTime'];
    if (raw is! String) return null;
    try {
      return stamp(raw);
    } catch (_) {
      return null;
    }
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
          ? 'Nie znaleziono aktywnych komunikatów. To nie gwarantuje bezpieczeństwa.'
          : 'Komunikaty dla miejscowości i jej regionu: ${active.length}.',
    };
    final snapshotTime = _snapshotTime();
    final urgentNational =
        nationalFresh &&
        national is Map &&
        national['hazardLevel'] == 'ACTIVE_DANGER';
    BuildContext? threatsSectionContext;
    void scrollToThreats() {
      final target = threatsSectionContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 350),
          alignment: 0.08,
        );
      }
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        key: const PageStorageKey('dashboard'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
        children: [
          Text(
            'Sytuacja teraz',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          if (localityLabel == null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Twoja okolica',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Wybierz miejscowość, aby zobaczyć ostrzeżenia w pobliżu.',
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: onChooseLocality,
                      icon: const Icon(Icons.my_location),
                      label: const Text('Ustaw lokalizację'),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            _statusCard(
              context,
              title: 'Twoja okolica',
              subtitle: localityLabel,
              status: local,
              fresh: localFresh,
              prominent: true,
              onTap: scrollToThreats,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onChooseLocality,
                icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
                label: const Text('Zmień miejscowość'),
              ),
            ),
          ],
          Text(
            '${_freshnessLabel()}${snapshotTime == null ? '' : ' • $snapshotTime'}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (!online && offlinePackage != null) ...[
            const SizedBox(height: 10),
            const _InfoBanner(
              icon: Icons.offline_pin_outlined,
              text:
                  'Tryb offline: ostatnie zapisane dane. Mogły pojawić się nowsze ostrzeżenia.',
            ),
          ] else if (error != null) ...[
            const SizedBox(height: 10),
            const _InfoBanner(
              icon: Icons.cloud_off_outlined,
              text:
                  'Nie udało się odświeżyć danych. Przeciągnij ekran w dół, aby spróbować ponownie.',
            ),
          ],
          if (urgentNational) ...[
            const SizedBox(height: 12),
            _statusCard(
              context,
              title: 'Polska',
              status: national,
              fresh: true,
              prominent: false,
              onTap: onOpenAlerts,
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              if (onOpenMap != null)
                OutlinedButton.icon(
                  onPressed: onOpenMap,
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Otwórz mapę'),
                ),
              OutlinedButton.icon(
                onPressed: onOpenAlerts,
                icon: const Icon(Icons.notifications_outlined),
                label: const Text('Wszystkie alerty'),
              ),
            ],
          ),
          if (localityLabel != null) ...[
            const SizedBox(height: 20),
            Builder(
              builder: (sectionContext) {
                threatsSectionContext = sectionContext;
                return Text(
                  'Istotne zagrożenia',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                );
              },
            ),
            const SizedBox(height: 10),
            if (localityAround == null)
              _EmptyState(
                icon: Icons.location_searching,
                title: loading ? 'Sprawdzamy okolicę' : 'Brak oceny lokalnej',
                text: 'Przeciągnij ekran w dół, aby odświeżyć dane.',
              )
            else if (active.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Brak istotnych aktywnych komunikatów w tym zakresie.',
                ),
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
            if (active.length > 3)
              TextButton(
                onPressed: onOpenAlerts,
                child: Text('Zobacz wszystkie (${active.length})'),
              ),
          ],
          const SizedBox(height: 16),
          ExpansionTile(
            key: const PageStorageKey('dashboard-national'),
            tilePadding: EdgeInsets.zero,
            leading: const Icon(Icons.public_outlined),
            title: const Text('Sytuacja w kraju'),
            children: [
              if (!urgentNational)
                _statusCard(
                  context,
                  title: 'Polska',
                  status: national,
                  fresh: nationalFresh,
                  prominent: false,
                  onTap: onOpenAlerts,
                ),
              const SizedBox(height: 8),
              SecurityLevelsSummaryCard(
                snapshot: snapshot,
                online: online,
                onTap: onOpenSecurityLevels,
              ),
              const SizedBox(height: 8),
            ],
          ),
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
                  'Odczyt okolicy: ${stamp(localityAround!.data['serverTime'] as String)}',
                ),
              const SizedBox(height: 8),
            ],
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
