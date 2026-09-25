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

  bool _active(SafetyEvent event, DateTime now) {
    if (event.data['lifecycle'] != 'ACTIVE' ||
        event.data['messageContext'] != 'ACTUAL' ||
        event.data['verification'] == 'REFUTED') {
      return false;
    }
    final end = DateTime.tryParse(event.data['validTo']?.toString() ?? '');
    if (end != null && !end.isAfter(now)) return false;
    final severity = event.data['severity']?.toString();
    return event.data['officialWarning'] == true ||
        severity == 'CRITICAL' ||
        severity == 'HIGH';
  }

  Color _statusColor(BuildContext context, dynamic status) {
    final scheme = Theme.of(context).colorScheme;
    final level = status is Map ? status['hazardLevel']?.toString() : null;
    return switch (level) {
      'ACTIVE_DANGER' => scheme.errorContainer,
      'CAUTION' => scheme.tertiaryContainer,
      'NO_ACTIVE_WARNINGS' => scheme.primaryContainer,
      _ => scheme.surfaceContainerHighest,
    };
  }

  IconData _statusIcon(dynamic status) {
    final level = status is Map ? status['hazardLevel']?.toString() : null;
    return switch (level) {
      'ACTIVE_DANGER' => Icons.warning_rounded,
      'CAUTION' => Icons.notification_important_outlined,
      'NO_ACTIVE_WARNINGS' => Icons.verified_user_outlined,
      _ => Icons.help_outline,
    };
  }

  String _statusText(dynamic status, bool fresh) {
    if (status is! Map) return 'Brak danych';
    final text = status['displayText']?.toString() ?? 'Brak danych';
    if (fresh) return text;
    if (!online && offlinePackage != null)
      return 'Ostatnia zapisana kopia: ' + text;
    return 'Brak świeżej oceny sytuacji';
  }

  Widget _statusRow(
    BuildContext context, {
    required String title,
    required dynamic status,
    required bool fresh,
    required IconData icon,
  }) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _statusColor(context, status),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(
                _statusText(status, fresh),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final national = snapshot?.data['nationalStatus'];
    final local = snapshot?.data['status'];
    final nationalFresh =
        online && (snapshot?.freshAt(now, national: true) ?? false);
    final localFresh = online && (snapshot?.freshAt(now) ?? false);
    final active = events
        .where((event) => _active(event, now))
        .take(5)
        .toList();

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        key: const PageStorageKey('dashboard'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Sytuacja teraz',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (backgroundSync || loading)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _statusRow(
                    context,
                    title: 'Polska',
                    status: national,
                    fresh: nationalFresh,
                    icon: _statusIcon(national),
                  ),
                  const SizedBox(height: 10),
                  _statusRow(
                    context,
                    title: localityLabel == null
                        ? 'Twoja okolica'
                        : localityLabel!,
                    status: local,
                    fresh: localFresh,
                    icon: Icons.location_on_outlined,
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: onChooseLocality,
                    icon: const Icon(Icons.edit_location_alt_outlined),
                    label: Text(
                      localityLabel == null
                          ? 'Ustaw swoją okolicę'
                          : 'Zmień swoją okolicę',
                    ),
                  ),
                  if (localityLabel != null && localityAround != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Dokładne zdarzenia w promieniu 20 km: ' +
                          localityAround!.nearbyEvents.length.toString() +
                          '. Komunikaty bez geometrii nadal liczą się dla województwa ' +
                          (regions[region] ?? region) +
                          '.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (!online && offlinePackage != null) ...[
            const SizedBox(height: 8),
            const _InfoBanner(
              icon: Icons.offline_pin_outlined,
              text:
                  'Tryb offline • ostatnia zapisana kopia. Brak nowych danych nie oznacza braku zagrożenia.',
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 8),
            _InfoBanner(icon: Icons.cloud_off_outlined, text: error!),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Istotne aktywne zagrożenia',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(
                onPressed: onOpenAlerts,
                child: const Text('Wszystkie'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (snapshot == null && offlinePackage == null)
            const _EmptyState(
              icon: Icons.cloud_download_outlined,
              title: 'Brak pobranych danych',
              text:
                  'Aplikacja spróbuje pobrać status automatycznie. Możesz też przeciągnąć ekran w dół.',
            )
          else if (active.isEmpty)
            const _EmptyState(
              icon: Icons.notifications_none_outlined,
              title: 'Brak istotnych aktywnych komunikatów w pobranych danych',
              text:
                  'To nie jest gwarancja bezpieczeństwa — ocena zależy od aktualności oficjalnych źródeł.',
            )
          else
            ...active.map(
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
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 32),
          const SizedBox(height: 10),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(text),
        ],
      ),
    ),
  );
}
