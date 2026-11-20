import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../model.dart';
import '../neptun.dart';
import '../security_levels.dart';
import '../shelter_panel.dart';
import '../watched_locations_panel.dart';

class MoreScreen extends StatelessWidget {
  final DataRepository repository;
  final Snapshot? snapshot;
  final bool online;
  final String region;
  final Future<void> Function(String) openLink;
  final Future<void> Function() call112;
  final Future<void> Function()? onWatchedLocationsChanged;

  const MoreScreen({
    super.key,
    required this.repository,
    required this.snapshot,
    required this.online,
    required this.region,
    required this.openLink,
    required this.call112,
    this.onWatchedLocationsChanged,
  });

  void _openSecurityLevels(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SecurityLevelsScreen(
          snapshot: snapshot,
          online: online,
          openSource: (url) => unawaited(openLink(url)),
        ),
      ),
    );
  }

  void _openShelters(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Schronienia')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ShelterPanel(
                key: ValueKey(
                  '${repository.api}:$region:${repository.dataGeneration}',
                ),
                repository: repository,
                region: region,
                initial: snapshot?.shelters,
                online: online,
                openLink: openLink,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          key: const PageStorageKey('more'),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            _MenuGroup(
              children: [
                _MenuRow(
                  icon: Icons.security_outlined,
                  title: 'Stopnie alarmowe',
                  subtitle: 'Zakres i ważność stopni ALFA–DELTA oraz CRP',
                  onTap: () => _openSecurityLevels(context),
                ),
                _MenuRow(
                  icon: Icons.home_work_outlined,
                  title: 'Schronienia',
                  subtitle: 'Najbliższe punkty i dane dostępne offline',
                  onTap: () => _openShelters(context),
                ),
                _MenuRow(
                  icon: Icons.timeline_outlined,
                  title: 'NEPTUN',
                  subtitle: 'Bieżące zgrubne zagrożenia i historia',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => NeptunScreen(
                        repository: repository,
                        openSource: openLink,
                      ),
                    ),
                  ),
                ),
                _MenuRow(
                  icon: Icons.radar_outlined,
                  title: 'Obserwowane miejsca',
                  subtitle: 'Zapisane miejscowości i powiadomienia',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => WatchedLocationsScreen(
                        repository: repository,
                        onPreferencesChanged: onWatchedLocationsChanged,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Pomoc', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            _MenuGroup(
              children: [
                _MenuRow(
                  icon: Icons.phone_outlined,
                  title: '112 • Numer alarmowy',
                  color: theme.colorScheme.error,
                  onTap: call112,
                ),
                _MenuRow(
                  icon: Icons.share_outlined,
                  title: 'Udostępnij „Jestem bezpieczny”',
                  onTap: () async {
                    await SharePlus.instance.share(
                      ShareParams(text: 'Jestem bezpieczny.'),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Oficjalne informacje', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            _MenuGroup(
              children: [
                for (final link in const [
                  (
                    'Rządowe Centrum Bezpieczeństwa',
                    'https://www.gov.pl/web/rcb',
                  ),
                  (
                    'Regionalny System Ostrzegania',
                    'https://komunikaty.tvp.pl/',
                  ),
                  (
                    'Państwowa Agencja Atomistyki',
                    'https://www.gov.pl/web/paa',
                  ),
                  ('CERT Polska', 'https://moje.cert.pl/komunikaty/'),
                ])
                  _MenuRow(
                    title: link.$1,
                    external: true,
                    onTap: () => openLink(link.$2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Aplikacja działa bez konta. Używa GPS na żądanie i nie zapisuje historii ruchu.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuGroup extends StatelessWidget {
  final List<Widget> children;

  const _MenuGroup({required this.children});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final row in children) ...[row, const Divider()],
    ],
  );
}

class _MenuRow extends StatelessWidget {
  final IconData? icon;
  final String title;
  final String? subtitle;
  final Color? color;
  final bool external;
  final VoidCallback onTap;

  const _MenuRow({
    this.icon,
    required this.title,
    this.subtitle,
    this.color,
    this.external = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: icon == null ? null : Icon(icon, color: color ?? muted),
      title: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(color: color),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
      trailing: Icon(
        external ? Icons.open_in_new_rounded : Icons.chevron_right_rounded,
        color: muted,
        size: external ? 17 : 22,
      ),
      onTap: onTap,
    );
  }
}
