import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../model.dart';
import '../neptun.dart';
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
  Widget build(BuildContext context) => ListView(
    key: const PageStorageKey('more'),
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
    children: [
      _ActionCard(
        icon: Icons.home_work_outlined,
        title: 'Schronienia',
        subtitle: 'Najbliższe punkty i zapisane dane offline',
        onTap: () => _openShelters(context),
      ),
      _ActionCard(
        icon: Icons.timeline_outlined,
        title: 'NEPTUN',
        subtitle: 'Bieżące zgrubne zagrożenia i historia',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                NeptunScreen(repository: repository, openSource: openLink),
          ),
        ),
      ),
      _ActionCard(
        icon: Icons.radar_outlined,
        title: 'Obserwowane miejsca',
        subtitle: 'Miejsca ważne dla Ciebie, bez śledzenia w tle',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => WatchedLocationsScreen(
              repository: repository,
              onPreferencesChanged: onWatchedLocationsChanged,
            ),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Text(
        'Pomoc',
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      FilledButton.icon(
        onPressed: call112,
        icon: const Icon(Icons.phone_outlined),
        label: const Text('112 • Numer alarmowy'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () async {
          await SharePlus.instance.share(
            ShareParams(text: 'Jestem bezpieczny.'),
          );
        },
        icon: const Icon(Icons.share_outlined),
        label: const Text('Udostępnij „Jestem bezpieczny”'),
      ),
      const SizedBox(height: 18),
      Text(
        'Oficjalne informacje',
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      for (final link in const [
        ('Rządowe Centrum Bezpieczeństwa', 'https://www.gov.pl/web/rcb'),
        ('Regionalny System Ostrzegania', 'https://komunikaty.tvp.pl/'),
        ('Państwowa Agencja Atomistyki', 'https://www.gov.pl/web/paa'),
        ('CERT Polska', 'https://moje.cert.pl/komunikaty/'),
      ])
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(link.$1),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => openLink(link.$2),
        ),
      const SizedBox(height: 8),
      Text(
        'Konto nie jest wymagane. GPS działa wyłącznie na żądanie i aplikacja nie zapisuje historii ruchu.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}
