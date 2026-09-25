import 'package:flutter/material.dart';

import '../model.dart';
import '../offline_packages.dart';
import '../ui/safety_event_card.dart';

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
    required this.onOpenEvent,
  });

  String _statusWord(dynamic status, bool fresh) {
    if (!fresh) return 'BRAK ŚWIEŻEJ OCENY';
    final level = status is Map ? status['hazardLevel']?.toString() : null;
    return switch (level) {
      'ACTIVE_DANGER' => 'POWAŻNE ZAGROŻENIE',
      'CAUTION' => 'OSTRZEŻENIA',
      'NO_ACTIVE_WARNINGS' => 'SPOKOJNIE',
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

  Widget _statusCard(
    BuildContext context, {
    required String title,
    String? subtitle,
    required dynamic status,
    required bool fresh,
    required bool prominent,
    VoidCallback? onTap,
  }) {
    final background = _statusBackground(context, status, fresh);
    final foreground = _statusForeground(context, status, fresh);
    final word = _statusWord(status, fresh);
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(prominent ? 24 : 18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(prominent ? 24 : 18),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(prominent ? 21 : 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(prominent ? 24 : 18),
            border: Border.all(
              color: foreground.withAlpha(prominent ? 115 : 70),
              width: prominent ? 2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _statusIcon(status, fresh),
                size: prominent ? 42 : 30,
                color: foreground,
              ),
              SizedBox(width: prominent ? 15 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.7,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: foreground),
                      ),
                    ],
                    SizedBox(height: prominent ? 8 : 5),
                    Text(
                      word,
                      style:
                          (prominent
                                  ? Theme.of(context).textTheme.headlineSmall
                                  : Theme.of(context).textTheme.titleLarge)
                              ?.copyWith(
                                color: foreground,
                                fontWeight: FontWeight.w900,
                              ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _statusDetail(status, fresh),
                      maxLines: prominent ? 3 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: foreground),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right_rounded, color: foreground),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final national = snapshot?.data['nationalStatus'];
    final local = snapshot?.data['status'];
    final nationalFresh =
        online && (snapshot?.freshAt(now, national: true) ?? false);
    final localFresh = online && (snapshot?.freshAt(now) ?? false);
    final active =
        events.where((event) => safetyEventIsSignificant(event, now)).toList()
          ..sort((a, b) {
            final severity = safetyEventPriority(
              a,
              now,
            ).compareTo(safetyEventPriority(b, now));
            if (severity != 0) return severity;
            return safetyEventTime(b).compareTo(safetyEventTime(a));
          });
    final localRelevant = localityAround == null
        ? 0
        : {
            ...localityAround!.nearbyEvents
                .map((item) => item.event)
                .where((event) => safetyEventIsSignificant(event, now))
                .map((event) => event.id),
            ...localityAround!.regionalEvents
                .where((event) => safetyEventIsSignificant(event, now))
                .map((event) => event.id),
          }.length;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        key: const PageStorageKey('dashboard'),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 26),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Sytuacja teraz',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              if (backgroundSync || loading)
                const SizedBox(
                  width: 21,
                  height: 21,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 11),
          _statusCard(
            context,
            title: 'Polska',
            status: national,
            fresh: nationalFresh,
            prominent: true,
          ),
          const SizedBox(height: 12),
          _statusCard(
            context,
            title: 'Twoja okolica',
            subtitle: localityLabel ?? 'Nie wybrano miejscowości',
            status: local,
            fresh: localFresh,
            prominent: false,
            onTap: onChooseLocality,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                localityLabel == null
                    ? Icons.add_location_alt_outlined
                    : Icons.location_on_outlined,
                size: 18,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  localityLabel == null
                      ? 'Ustaw miejscowość, aby szybciej oceniać swoją okolicę.'
                      : localityAround == null
                      ? 'Odświeżamy informacje dla wybranej okolicy.'
                      : 'Istotne komunikaty lokalne lub regionalne: $localRelevant.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextButton(
                onPressed: onChooseLocality,
                child: Text(localityLabel == null ? 'Ustaw' : 'Zmień'),
              ),
            ],
          ),
          if (!online && offlinePackage != null) ...[
            const SizedBox(height: 4),
            const _InfoBanner(
              icon: Icons.offline_pin_outlined,
              text:
                  'Tryb offline: pokazujemy ostatnie zapisane dane. Mogły pojawić się nowsze ostrzeżenia.',
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 6),
            _InfoBanner(
              icon: Icons.cloud_off_outlined,
              text: 'Nie udało się pobrać świeżych danych. $error',
            ),
          ],
          const SizedBox(height: 21),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Istotne aktywne zagrożenia',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              TextButton.icon(
                onPressed: onOpenAlerts,
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: const Text('Wszystkie'),
              ),
            ],
          ),
          const SizedBox(height: 7),
          if (snapshot == null && offlinePackage == null)
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
                .take(5)
                .map(
                  (event) => SafetyEventCard(
                    event: event,
                    compact: true,
                    onTap: () => onOpenEvent(event),
                  ),
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
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );
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
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 32),
        const SizedBox(height: 10),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(text),
      ],
    ),
  );
}
