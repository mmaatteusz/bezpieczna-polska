import 'ukraine.dart';
import 'radiation.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

import 'model.dart';
import 'shelter_map.dart';
import 'security_levels.dart';
import 'shelter_panel.dart';
import 'event_details.dart';
import 'status_explanation.dart';
import 'source_status.dart';
import 'watched_locations_panel.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    SafetyApp(
      repository: DataRepository(await SharedPreferences.getInstance()),
    ),
  );
}

class SafetyApp extends StatefulWidget {
  final DataRepository repository;
  const SafetyApp({super.key, required this.repository});
  @override
  State<SafetyApp> createState() => _SafetyAppState();
}

class _SafetyAppState extends State<SafetyApp> {
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Bezpieczna Polska',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF127363)),
      scaffoldBackgroundColor: const Color(0xFFF4F7F7),
    ),
    darkTheme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF70D7BF),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF101A21),
    ),
    themeMode: widget.repository.dark ? ThemeMode.dark : ThemeMode.light,
    home: Home(repository: widget.repository, onTheme: () => setState(() {})),
  );
}

class Home extends StatefulWidget {
  final DataRepository repository;
  final VoidCallback onTheme;
  const Home({super.key, required this.repository, required this.onTheme});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  int page = 0, generation = 0;
  bool online = false, loading = false, ukraine = false;
  late String region;
  Snapshot? snapshot;
  String? error;
  Timer? timer, refreshTimer;
  String statusFilter = 'Wszystkie',
      sourceFilter = 'Wszystkie',
      typeFilter = 'Wszystkie',
      query = '';
  Map<String, int> seen = {};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    region = widget.repository.region;
    snapshot = widget.repository.cached(region);
    loadSeen();
    timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    if (widget.repository.api.isNotEmpty) unawaited(refresh());
    refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted &&
          !loading &&
          widget.repository.api.isNotEmpty &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(refresh());
      }
    });
  }

  void loadSeen() {
    try {
      seen = Map<String, int>.from(
        jsonDecode(
              widget.repository.prefs.getString(
                    'seen:${widget.repository.api}:$region',
                  ) ??
                  '{}',
            )
            as Map,
      );
    } catch (_) {
      seen = {};
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.repository.api.isNotEmpty) {
      unawaited(refresh());
    }
  }

  Future<void> refresh() async {
    final ticket = ++generation, target = region;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final s = await widget.repository.refresh(target);
      if (mounted && ticket == generation) {
        setState(() {
          snapshot = s;
          online = true;
        });
      }
    } catch (failure) {
      if (mounted && ticket == generation) {
        setState(() {
          online = false;
          error = apiFailureMessage(failure);
        });
      }
    } finally {
      if (mounted && ticket == generation) setState(() => loading = false);
    }
  }

  Future<void> changeRegion(String value) async {
    ++generation;
    await widget.repository.setRegion(value);
    if (!mounted) return;
    setState(() {
      region = value;
      snapshot = widget.repository.cached(value);
      online = false;
      loading = false;
      error = null;
      loadSeen();
    });
    if (widget.repository.api.isNotEmpty) await refresh();
  }

  List<SafetyEvent> get events => snapshot?.alertEvents ?? [];
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BEZPIECZNA POLSKA',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(letterSpacing: 2),
          ),
          Text(
            [
              'Twoje bezpieczeństwo',
              'Mapa bezpieczeństwa',
              'Centrum alertów',
              'Znajdź schronienie',
              'Pomoc i przygotowanie',
            ][page],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Ustawienia',
          onPressed: settings,
          icon: const Icon(Icons.tune),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.location_on_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String>(
                    value: region,
                    isExpanded: true,
                    underline: const SizedBox(),
                    items: regions.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(
                              e.value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) unawaited(changeRegion(v));
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Odśwież',
                  onPressed: loading || widget.repository.api.isEmpty
                      ? null
                      : refresh,
                  icon: loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: notice(error!, Icons.cloud_off),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: switch (page) {
                  0 => statusPage(),
                  1 => mapPage(),
                  2 => rcbPage(),
                  3 => shelterPage(),
                  _ => helpPage(),
                },
              ),
            ),
          ),
        ],
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: page,
      onDestinationSelected: (i) => setState(() => page = i),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.shield_outlined),
          label: 'Status',
        ),
        NavigationDestination(icon: Icon(Icons.map_outlined), label: 'Mapa'),
        NavigationDestination(
          icon: Icon(Icons.campaign_outlined),
          label: 'Alerty',
        ),
        NavigationDestination(
          icon: Icon(Icons.home_work_outlined),
          label: 'Schronienie',
        ),
        NavigationDestination(
          icon: Icon(Icons.support_outlined),
          label: 'Pomoc',
        ),
      ],
    ),
  );
  Widget notice(String text, IconData icon) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    ),
  );
  Widget heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 12),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
  Widget empty(String title, String text, IconData icon) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 32),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(text),
        ],
      ),
    ),
  );
  Widget badge(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(text, style: Theme.of(context).textTheme.labelSmall),
  );
  Widget statusCard(bool national) {
    final fresh =
        online &&
        (snapshot?.freshAt(DateTime.now(), national: national) ?? false);
    final status = snapshot?.data[national ? 'nationalStatus' : 'status'];
    final danger = fresh && status?['hazardLevel'] == 'ACTIVE_DANGER';
    return Card(
      color: danger
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              national ? 'STATUS POLSKI' : 'TWOJA OKOLICA • ${regions[region]}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 14),
            Text(
              snapshot?.statusText(
                    DateTime.now(),
                    online: online,
                    national: national,
                  ) ??
                  'Brak bieżącej oceny sytuacji',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              fresh
                  ? 'Ocena obejmuje wyłącznie monitorowane źródła.'
                  : 'Brak aktualnych danych nie potwierdza bezpieczeństwa.',
            ),
            const SizedBox(height: 12),
            Text(
              'Dane: ${stamp(snapshot?.data['serverTime'])}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (status is Map)
              StatusExplanation(status: status, events: snapshot?.events ?? []),
          ],
        ),
      ),
    );
  }

  List<Widget> statusPage() {
    final changed = events
        .where((e) => e.revision > (seen[e.id] ?? 0))
        .toList();
    return [
      statusCard(true),
      statusCard(false),
      OutlinedButton.icon(
        onPressed: () => setState(() {
          page = 1;
          ukraine = true;
        }),
        icon: const Icon(Icons.public),
        label: const Text('Ukraina • oficjalne alarmy'),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.radar_outlined),
          title: const Text('Wokół mnie'),
          subtitle: const Text(
            'Jednorazowy GPS lub zapisane miejsca. Bez ciągłego śledzenia i bez historii ruchu.',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  WatchedLocationsScreen(repository: widget.repository),
            ),
          ),
        ),
      ),
      if (widget.repository.api.isEmpty)
        notice(
          'Ta wersja aplikacji nie ma skonfigurowanego połączenia z usługą. Wymagana jest aktualizacja aplikacji.',
          Icons.cloud_off,
        ),
      RadiationPanel(snapshot: snapshot, online: online, openSource: openLink),
      SecurityLevelsPanel(
        snapshot: snapshot,
        online: online,
        openSource: openLink,
      ),
      if (events.any((e) => e.data['eventType'] == 'CYBER')) ...[
        heading('Cyberbezpieczeństwo'),
        notice(
          'Komunikaty cyber są prezentowane osobno i nie podnoszą automatycznie statusu zagrożenia fizycznego.',
          Icons.security_outlined,
        ),
        ...events
            .where((e) => e.data['eventType'] == 'CYBER')
            .take(3)
            .map(eventCard),
      ],
      if (events.any(
        (e) =>
            e.data['eventType'] == 'BORDER' &&
            e.sources.any((s) => s['id'] == 'SG'),
      )) ...[
        heading('Granice • Straż Graniczna'),
        notice(
          'Pokazujemy wyłącznie operacyjne informacje o zamknięciach, ograniczeniach, kontrolach i utrudnieniach granicznych. Taki komunikat nie podnosi automatycznie głównego statusu zagrożenia.',
          Icons.travel_explore_outlined,
        ),
        ...events
            .where(
              (e) =>
                  e.data['eventType'] == 'BORDER' &&
                  e.sources.any((s) => s['id'] == 'SG'),
            )
            .take(3)
            .map(eventCard),
      ],
      if (events.any(
        (e) => e.sources.any(
          (s) => s['id'] == 'POLICE' || s['id'] == 'PSP_INCIDENTS',
        ),
      )) ...[
        heading('Zdarzenia służb'),
        notice(
          'Pokazujemy tylko zdarzenia Policji i PSP istotne sytuacyjnie. Pojedyncza publikacja służby nie podnosi automatycznie statusu całego województwa.',
          Icons.local_fire_department_outlined,
        ),
        ...events
            .where(
              (e) => e.sources.any(
                (s) => s['id'] == 'POLICE' || s['id'] == 'PSP_INCIDENTS',
              ),
            )
            .take(5)
            .map(eventCard),
      ],
      if (events.any((e) => e.isRso)) ...[
        heading('Regionalny System Ostrzegania'),
        ...events.where((e) => e.isRso).take(5).map(eventCard),
      ],
      const SizedBox(height: 12),
      notice(
        'Wersja rozwojowa 0.1.0-alpha.11 • Powiadomienia push nie są aktywne.',
        Icons.science_outlined,
      ),
      heading('Od ostatniej wizyty'),
      if (changed.isEmpty)
        empty(
          'Brak nowych zapisanych informacji',
          'Nie jest to potwierdzenie braku zagrożeń.',
          Icons.history,
        ),
      ...changed.take(5).map(eventCard),
      if (changed.isNotEmpty)
        TextButton(
          onPressed: () async {
            final values = {for (final e in events) e.id: e.revision};
            await widget.repository.prefs.setString(
              'seen:${widget.repository.api}:$region',
              jsonEncode(values),
            );
            if (mounted) setState(() => seen = values);
          },
          child: const Text('Oznacz zmiany jako przeczytane'),
        ),
      heading('Źródła i aktualność'),
      if (snapshot == null)
        empty(
          'Źródła niepołączone',
          'RCB, RSO i pozostałe kategorie pokażą swój stan po synchronizacji.',
          Icons.hub_outlined,
        ),
      ...?((snapshot?.data['sources'] as List?)?.take(4).map((raw) {
        final s = raw as Map;
        final state = (s['healthStatus'] ?? s['state'] ?? 'UNKNOWN').toString();
        return Card(
          child: ListTile(
            leading: Icon(
              state == 'HEALTHY'
                  ? Icons.check_circle_outline
                  : state == 'STALE'
                  ? Icons.schedule_outlined
                  : Icons.info_outline,
            ),
            title: Text(s['name'] as String),
            trailing: state == 'STALE' ? badge('STALE') : null,
            subtitle: Text(
              '${sourceStateLabel(state)}\nOstatnia poprawna synchronizacja: ${stamp(s['lastSuccess'])}',
            ),
          ),
        );
      })),
      if (snapshot != null)
        OutlinedButton.icon(
          onPressed: openSources,
          icon: const Icon(Icons.hub_outlined),
          label: const Text('Pokaż wszystkie źródła i diagnostykę'),
        ),
      heading('Zapisane komunikaty regionu'),
      ...events.take(30).map(eventCard),
    ];
  }

  Widget eventCard(SafetyEvent e) => Card(
    child: InkWell(
      onTap: () => details(e),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                badge(e.sources.first['name'] as String),
                badge(e.badge),
                badge(e.provenance),
                if (e.sourceSummary != null) badge(e.sourceSummary!),
                if (e.hasConflictingReports)
                  badge('RÓŻNICE MIĘDZY KOMUNIKATAMI'),
                if (eventSourceState(e) == 'STALE')
                  badge('STALE • DANE NIEAKTUALNE'),
              ],
            ),
            const SizedBox(height: 12),
            Text(e.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(e.description, maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 10),
            Text(
              e.areas.isEmpty
                  ? 'Obszar nieustalony — sprawdź treść'
                  : e.areas.map((r) => regions[r] ?? r).join(', '),
            ),
            Text(
              'Publikacja: ${e.data['publishedAt'] == null ? (e.data['publicationDate'] ?? 'Nie podano') : stamp(e.data['publishedAt'])}',
            ),
            if (e.data['locationText'] != null)
              Text('Obszar według źródła: ${e.data['locationText']}'),
            Text('Pobrano: ${stamp(e.data['retrievedAt'])}'),
          ],
        ),
      ),
    ),
  );
  bool alertStatusMatches(SafetyEvent e) {
    final lifecycle = e.data['lifecycle'] as String;
    final correction = e.data['correction'];
    final expired =
        DateTime.tryParse(
          e.data['validTo'] as String? ?? '',
        )?.isBefore(DateTime.now()) ??
        false;
    return switch (statusFilter) {
      'Aktywne' => lifecycle == 'ACTIVE' && !expired,
      'Zakończone' =>
        ['ENDED', 'CANCELLED', 'EXPIRED'].contains(lifecycle) || expired,
      'Nieustalone' => lifecycle == 'UNKNOWN',
      'Korekty' =>
        correction != null ||
            e.revision > 1 ||
            ['REFUTED', 'DISPUTED'].contains(e.data['verification']),
      _ => true,
    };
  }

  String eventSourceState(SafetyEvent e) {
    final sources = snapshot?.data['sources'];
    if (sources is! List) return 'UNKNOWN';
    for (final eventSource in e.sources) {
      for (final raw in sources) {
        if (raw is Map && raw['id'] == eventSource['id']) {
          return (raw['healthStatus'] ?? raw['state'] ?? 'UNKNOWN').toString();
        }
      }
    }
    return 'UNKNOWN';
  }

  String eventTypeLabel(String value) => switch (value) {
    'AIR' => 'Powietrzne',
    'BORDER' => 'Granica',
    'CYBER' => 'Cyber',
    'RADIATION' => 'Radiacja',
    'FIRE' => 'Pożar',
    'EXPLOSION' => 'Wybuch',
    'HAZMAT' => 'Zagrożenie chemiczne',
    'RESCUE' => 'Ratownictwo',
    'PUBLIC_SAFETY' => 'Bezpieczeństwo publiczne',
    'EVACUATION' => 'Ewakuacja',
    'OUTAGE' => 'Awarie',
    'WEATHER' => 'Pogoda',
    'OTHER' => 'Inne',
    _ => value,
  };

  String sourceLabel(String value) => switch (value) {
    'POLICE' => 'Policja',
    'PSP_INCIDENTS' => 'PSP',
    'CSIRT_GOV' => 'CSIRT GOV',
    _ => value,
  };

  List<Widget> rcbPage() {
    final sourceOptions = <String>{
      'Wszystkie',
      'RCB',
      'RSO',
      'WCZK',
      'PAA',
      'CERT',
      'CSIRT_GOV',
      'SG',
      'POLICE',
      'PSP_INCIDENTS',
      ...events.expand((e) => e.sources.map((s) => s['id'].toString())),
    }.toList();
    final typeOptions = <String>{
      'Wszystkie',
      'FIRE',
      'EXPLOSION',
      'RESCUE',
      'HAZMAT',
      'PUBLIC_SAFETY',
      ...events.map((e) => e.data['eventType'].toString()),
    }.toList();
    if (!sourceOptions.contains(sourceFilter)) sourceFilter = 'Wszystkie';
    if (!typeOptions.contains(typeFilter)) typeFilter = 'Wszystkie';
    final normalized = query.trim().toLowerCase();
    final list = events.where((e) {
      final text = e.reports
          .map((r) => '${r.title} ${r.description}')
          .join(' ')
          .toLowerCase();
      final sourceOk =
          sourceFilter == 'Wszystkie' ||
          (sourceFilter == 'WCZK' && e.isWczk) ||
          e.sources.any((s) => s['id'] == sourceFilter);
      final typeOk =
          typeFilter == 'Wszystkie' ||
          e.reports.any((r) => r.data['eventType'] == typeFilter);
      return text.contains(normalized) &&
          sourceOk &&
          typeOk &&
          e.reports.any(alertStatusMatches);
    }).toList();
    return [
      TextField(
        decoration: const InputDecoration(
          labelText: 'Szukaj w alertach',
          prefixIcon: Icon(Icons.search),
        ),
        onChanged: (v) => setState(() => query = v),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children:
            ['Wszystkie', 'Aktywne', 'Zakończone', 'Nieustalone', 'Korekty']
                .map(
                  (s) => ChoiceChip(
                    label: Text(s),
                    selected: statusFilter == s,
                    onSelected: (_) => setState(() => statusFilter = s),
                  ),
                )
                .toList(),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: sourceFilter,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Źródło'),
              items: sourceOptions
                  .map(
                    (s) =>
                        DropdownMenuItem(value: s, child: Text(sourceLabel(s))),
                  )
                  .toList(),
              onChanged: (v) => setState(() => sourceFilter = v ?? 'Wszystkie'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: typeFilter,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Kategoria'),
              items: typeOptions
                  .map(
                    (s) => DropdownMenuItem(
                      value: s,
                      child: Text(s == 'Wszystkie' ? s : eventTypeLabel(s)),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => typeFilter = v ?? 'Wszystkie'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Text('Pokazano ${list.length} z ${events.length} zapisanych alertów'),
      if (list.isEmpty)
        empty(
          'Brak alertów dla tych filtrów',
          'Zmień filtr lub sprawdź stan synchronizacji źródeł.',
          Icons.campaign_outlined,
        ),
      ...list.map(eventCard),
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: () => openLink('https://www.gov.pl/web/rcb'),
            icon: const Icon(Icons.open_in_new),
            label: const Text('RCB'),
          ),
          OutlinedButton.icon(
            onPressed: () => openLink('https://komunikaty.tvp.pl/'),
            icon: const Icon(Icons.open_in_new),
            label: const Text('RSO'),
          ),
          OutlinedButton.icon(
            onPressed: () => openLink('https://moje.cert.pl/komunikaty/'),
            icon: const Icon(Icons.open_in_new),
            label: const Text('CERT Polska'),
          ),
          OutlinedButton.icon(
            onPressed: () => openLink('https://www.csirt.gov.pl/cer/rss'),
            icon: const Icon(Icons.open_in_new),
            label: const Text('CSIRT GOV'),
          ),
          OutlinedButton.icon(
            onPressed: () =>
                openLink('https://www.strazgraniczna.pl/pl/aktualnosci'),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Straż Graniczna'),
          ),
          OutlinedButton.icon(
            onPressed: () => openLink('https://policja.pl/pol/aktualnosci'),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Policja'),
          ),
          OutlinedButton.icon(
            onPressed: () =>
                openLink('https://www.gov.pl/web/kgpsp/aktualnosci'),
            icon: const Icon(Icons.open_in_new),
            label: const Text('PSP'),
          ),
        ],
      ),
    ];
  }

  List<Widget> mapPage() => [
    SegmentedButton<bool>(
      segments: const [
        ButtonSegment(value: false, label: Text('Polska')),
        ButtonSegment(value: true, label: Text('Ukraina')),
      ],
      selected: {ukraine},
      onSelectionChanged: (v) => setState(() => ukraine = v.first),
    ),
    const SizedBox(height: 12),
    if (ukraine)
      UkrainePanel(repository: widget.repository, openSource: openLink)
    else
      ShelterMap(
        radiation: snapshot?.data['radiation'],
        radiationOnline: online,
        key: ValueKey(
          'map:${widget.repository.api}:$region:$ukraine:${widget.repository.dataGeneration}',
        ),
        repository: widget.repository,
        region: region,
        ukraine: ukraine,
        openLink: openLink,
      ),
    const SizedBox(height: 12),
    notice(
      ukraine
          ? 'Alarmy Ukrainy są osobnym kontekstem. Brak oznaczeń nie oznacza braku alarmów.'
          : 'Mapa pokazuje punkty schronienia wg PSP. Liczby grupują punkty w widocznym obszarze. Przybliż mapę, aby wybrać punkt. Mapa nie potwierdza bieżącej dostępności i nie służy do nawigacji. Offline dostępne są tylko zapisane obszary; podkład mapy wymaga internetu lub wcześniejszego cache.',
      Icons.info_outline,
    ),
    if (!ukraine) ...events.where((e) => e.hasPoint).take(20).map(eventCard),
  ];
  List<Widget> shelterPage() => [
    ShelterPanel(
      key: ValueKey(
        '${widget.repository.api}:$region:${widget.repository.dataGeneration}',
      ),
      repository: widget.repository,
      region: region,
      initial: snapshot?.shelters,
      online: online,
      openLink: openLink,
    ),
  ];
  List<Widget> helpPage() => [
    FilledButton.icon(
      onPressed: call112,
      icon: const Icon(Icons.phone_outlined),
      label: const Text('112 • Numer alarmowy'),
    ),
    heading('Jestem bezpieczny'),
    const Text(
      'Udostępnij krótką wiadomość przez wybraną aplikację. Lokalizacja nie jest dołączana.',
    ),
    OutlinedButton.icon(
      onPressed: () async {
        await SharePlus.instance.share(ShareParams(text: 'Jestem bezpieczny.'));
      },
      icon: const Icon(Icons.share_outlined),
      label: const Text('Udostępnij „Jestem bezpieczny”'),
    ),
    heading('Oficjalne informacje'),
    ...[
      ('Rządowe Centrum Bezpieczeństwa', 'https://www.gov.pl/web/rcb'),
      ('Regionalny System Ostrzegania', 'https://komunikaty.tvp.pl/'),
      ('Państwowa Agencja Atomistyki', 'https://www.gov.pl/web/paa'),
      ('CERT Polska', 'https://moje.cert.pl/komunikaty/'),
      ('CSIRT GOV', 'https://www.csirt.gov.pl/cer/rss'),
      ('Straż Graniczna', 'https://www.strazgraniczna.pl/pl/aktualnosci'),
      ('Policja', 'https://policja.pl/pol/aktualnosci'),
      ('Państwowa Straż Pożarna', 'https://www.gov.pl/web/kgpsp/aktualnosci'),
    ].map(
      (e) => Card(
        child: ListTile(
          title: Text(e.$1),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => openLink(e.$2),
        ),
      ),
    ),
    heading('Prywatność'),
    const Text(
      'Konto jest niewymagane. GPS jest używany wyłącznie po naciśnięciu „Znajdź najbliższe schronienie”; pozycja nie jest zapisywana ani śledzona w tle. Region, ustawienia i kopie komunikatów pozostają na urządzeniu. Serwer przy odświeżaniu poznaje wybrany region i dane połączenia. Przy wyszukiwaniu najbliższego schronienia serwer otrzymuje jednorazowo współrzędne potrzebne do obliczenia odległości. Linki otwierają zewnętrzną przeglądarkę.',
    ),
    const SizedBox(height: 16),
    notice(
      'Niezależny projekt rozwojowy. Nie zastępuje komunikatów służb ani numeru 112.',
      Icons.info_outline,
    ),
  ];
  Future<void> call112() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Otworzyć telefon z numerem 112?'),
        content: const Text('Połączenie wykonasz w aplikacji telefonu.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Otwórz telefon'),
          ),
        ],
      ),
    );
    if (yes == true) {
      try {
        final ok = await launchUrl(Uri(scheme: 'tel', path: '112'));
        if (!ok) throw StateError('Dialer');
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Otwórz telefon i wybierz 112.')),
          );
        }
      }
    }
  }

  Future<void> openLink(String url) async {
    final u = Uri.tryParse(url);
    if (u == null || u.scheme != 'https' || u.userInfo.isNotEmpty) return;
    try {
      if (!await launchUrl(u, mode: LaunchMode.externalApplication)) {
        throw StateError('Browser');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nie udało się otworzyć przeglądarki.')),
        );
      }
    }
  }

  void openSources() {
    final raw = snapshot?.data['sources'];
    final sources = raw is List
        ? raw.whereType<Map>().map((s) => Map<String, dynamic>.from(s)).toList()
        : <Map<String, dynamic>>[];
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SourceStatusPage(sources: sources, openLink: openLink),
      ),
    );
  }

  void details(SafetyEvent e) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => EventDetailsPage(
          event: e,
          repository: widget.repository,
          openLink: openLink,
        ),
      ),
    );
  }

  Future<void> settings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, update) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Ustawienia',
                    style: Theme.of(sheet).textTheme.titleLarge,
                  ),
                  SwitchListTile(
                    title: const Text('Tryb ciemny'),
                    value: widget.repository.dark,
                    onChanged: (v) async {
                      await widget.repository.prefs.setBool('dark', v);
                      widget.onTheme();
                      update(() {});
                    },
                  ),
                  TextButton(
                    onPressed: () async {
                      ++generation;
                      await widget.repository.clearData();
                      if (mounted) {
                        setState(() {
                          snapshot = null;
                          online = false;
                          loading = false;
                          seen = {};
                        });
                      }
                      if (sheet.mounted) Navigator.pop(sheet);
                    },
                    child: const Text('Usuń zapisane komunikaty'),
                  ),
                  if (widget.repository.developerSettingsEnabled)
                    ListTile(
                      title: const Text('Developer Settings'),
                      leading: const Icon(Icons.developer_mode),
                      onTap: () {
                        Navigator.pop(sheet);
                        unawaited(developerSettings());
                      },
                    ),
                  const Text(
                    '0.1.0-alpha.11 • Push nieaktywny • GPS tylko na żądanie',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> developerSettings() async {
    if (!widget.repository.developerSettingsEnabled) return;
    final controller = TextEditingController(
      text: widget.repository.developerApi,
    );
    String? validation;
    await showDialog<void>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          title: const Text('Developer Settings'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Adres z buildu: ${widget.repository.buildApi.isEmpty ? "brak" : widget.repository.buildApi}',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Backend URL (HTTPS)',
                    helperText: 'Puste pole przywraca konfigurację buildu.',
                    errorText: validation,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Anuluj'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  ++generation;
                  await widget.repository.setDeveloperApi(controller.text);
                  if (dialog.mounted) Navigator.pop(dialog);
                  if (mounted) {
                    setState(() {
                      snapshot = widget.repository.cached(region);
                      online = false;
                      loading = false;
                      loadSeen();
                    });
                    if (widget.repository.api.isNotEmpty) await refresh();
                  }
                } catch (_) {
                  update(() => validation = 'Wymagany poprawny adres HTTPS.');
                }
              },
              child: const Text('Zapisz i połącz'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }
}

String sourceStateLabel(String state) => switch (state) {
  'NOT_CONFIGURED' => 'Integracja oczekuje',
  'HEALTHY' => 'Dane aktualne',
  'BROKEN' => 'Błąd synchronizacji',
  'STALE' => 'STALE • dane nieaktualne',
  'DEGRADED' => 'Niepełne dane',
  _ => 'Brak aktualnego połączenia',
};
