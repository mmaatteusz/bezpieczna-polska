import 'neptun.dart';
import 'radiation.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

import 'model.dart';
import 'shelter_map.dart';
import 'security_levels.dart';
import 'shelter_panel.dart';
import 'event_details.dart';
import 'source_status.dart';
import 'watched_locations_panel.dart';
import 'push_notifications.dart';
import 'offline_packages.dart';
import 'offline_repository.dart';
import 'offline_data_screen.dart';
import 'build_config.dart';
import 'app_version.dart';

String? localityRegionSeed(String currentRegion) => currentRegion == 'PL' ? null : currentRegion;

Future<void> main() async {
  validateBuildConfiguration();
  WidgetsFlutterBinding.ensureInitialized();
  final repository = DataRepository(await SharedPreferences.getInstance());
  final pushAdapter =
      await FirebasePushPlatformAdapter.fromBuildConfiguration();
  runApp(
    SafetyApp(
      repository: repository,
      pushManager: PushManager(repository, pushAdapter),
    ),
  );
}

class SafetyApp extends StatefulWidget {
  final DataRepository repository;
  final PushManager? pushManager;
  const SafetyApp({super.key, required this.repository, this.pushManager});
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
    home: Home(
      repository: widget.repository,
      pushManager: widget.pushManager,
      onTheme: () => setState(() {}),
    ),
  );
}

class Home extends StatefulWidget {
  final DataRepository repository;
  final PushManager? pushManager;
  final VoidCallback onTheme;
  const Home({
    super.key,
    required this.repository,
    this.pushManager,
    required this.onTheme,
  });
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  int page = 0, generation = 0;
  bool online = false, loading = false, backgroundSync = false;
  late String region;
  String? localityLabel;
  Snapshot? snapshot;
  AroundResult? localityAround;
  OfflineRegionPackage? offlinePackageData;
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
    if (widget.pushManager != null) {
      unawaited(widget.pushManager!.initializeWithoutPrompt());
    }
    region = widget.repository.region;
    localityLabel = widget.repository.primaryLocationLabel;
    snapshot = widget.repository.cached(region);
    unawaited(loadOffline());
    loadSeen();
    timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    if (widget.repository.api.isNotEmpty) unawaited(startupSync());
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

  Future<void> loadOffline() async {
    final target = region;
    final package = await widget.repository.offlinePackage(target);
    Snapshot? fallback;
    if (package != null) {
      try {
        fallback = Snapshot.parse(jsonEncode(package.snapshot));
      } catch (_) {
        fallback = null;
      }
    }
    if (!mounted || target != region) return;
    setState(() {
      offlinePackageData = package;
      if (!online && fallback != null) snapshot = fallback;
    });
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
        await loadOffline();
      }
    } finally {
      if (mounted && ticket == generation) setState(() => loading = false);
    }
  }

  Future<void> startupSync() async {
    if (backgroundSync || widget.repository.api.isEmpty) return;
    final target = region;
    setState(() => backgroundSync = true);

    Future<void> ignoreFailure(Future<dynamic> Function() action) async {
      try {
        await action();
      } catch (_) {
        // The main snapshot error is already surfaced by refresh().
        // Secondary caches keep their previous LAST KNOWN GOOD copy.
      }
    }

    try {
      await refresh();
      if (!mounted || target != region || widget.repository.api.isEmpty) return;

      final existingPackage = await widget.repository.offlinePackage(target);
      final shouldRefreshOffline =
          existingPackage == null ||
          DateTime.now().toUtc().difference(existingPackage.createdAt) >
              const Duration(hours: 6);

      await Future.wait([
        ignoreFailure(widget.repository.refreshNeptun),
        if (shouldRefreshOffline)
          ignoreFailure(() => widget.repository.downloadOfflinePackage(target)),
      ]);
      await refreshPrimaryLocation(target);
      if (mounted && target == region) await loadOffline();
    } finally {
      if (mounted) {
        setState(() => backgroundSync = false);
        if (target != region && widget.repository.api.isNotEmpty) {
          unawaited(startupSync());
        }
      }
    }
  }

  Future<void> refreshPrimaryLocation(String target) async {
    final latitude = widget.repository.primaryLocationLatitude;
    final longitude = widget.repository.primaryLocationLongitude;
    if (latitude == null ||
        longitude == null ||
        widget.repository.primaryLocationLabel == null) {
      if (mounted && target == region) setState(() => localityAround = null);
      return;
    }

    AroundResult? result;
    try {
      result = await widget.repository.around(
        latitude,
        longitude,
        radiusKm: 20,
        regionId: target,
      );
    } catch (_) {
      result = await widget.repository.offlineAround(
        latitude,
        longitude,
        radiusKm: 20,
        regionId: target,
      );
    }
    if (mounted && target == region) {
      setState(() => localityAround = result);
    }
  }

  String? regionFromPlacemark(Placemark placemark) {
    String normalize(String value) => value
        .toLowerCase()
        .replaceAll('województwo', '')
        .replaceAll('woj.', '')
        .replaceAll(RegExp(r'[^a-ząćęłńóśźż]'), '');
    final area = normalize(placemark.administrativeArea ?? '');
    if (area.isEmpty) return null;
    for (final entry in regions.entries.where((e) => e.key != 'PL')) {
      if (normalize(entry.value) == area) return entry.key;
    }
    return null;
  }

  Future<void> chooseLocality() async {
    final queryController = TextEditingController();
    String? foundLabel;
    double? foundLatitude, foundLongitude;
    String? selectedRegion = localityRegionSeed(region);
    var searching = false;
    String? validation;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Wybierz swoją okolicę'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Wpisz miasto lub wieś. Współrzędne są ustalane automatycznie i nie są pokazywane w interfejsie.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: queryController,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    labelText: 'Miasto lub wieś',
                    hintText: 'np. Bydgoszcz albo Osielsko',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) {},
                ),
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  onPressed: searching
                      ? null
                      : () async {
                          final query = queryController.text.trim();
                          if (query.length < 2) {
                            update(
                              () => validation = 'Wpisz nazwę miejscowości.',
                            );
                            return;
                          }
                          update(() {
                            searching = true;
                            validation = null;
                          });
                          try {
                            final geocoder = Geocoding();
                            final locations = await geocoder
                                .locationFromAddress(
                                  '$query, Polska',
                                  locale: const Locale('pl', 'PL'),
                                );
                            if (locations.isEmpty) {
                              throw const FormatException();
                            }
                            final point = locations.first;
                            var label = query;
                            try {
                              final marks = await geocoder
                                  .placemarkFromCoordinates(
                                    point.latitude,
                                    point.longitude,
                                    locale: const Locale('pl', 'PL'),
                                  );
                              if (marks.isNotEmpty) {
                                final mark = marks.first;
                                final parts = <String>[
                                  if ((mark.locality ?? '').trim().isNotEmpty)
                                    mark.locality!.trim(),
                                  if ((mark.subAdministrativeArea ?? '')
                                          .trim()
                                          .isNotEmpty &&
                                      mark.subAdministrativeArea!.trim() !=
                                          mark.locality?.trim())
                                    mark.subAdministrativeArea!.trim(),
                                ];
                                if (parts.isNotEmpty) {
                                  label = parts.toSet().join(', ');
                                }
                                selectedRegion =
                                    regionFromPlacemark(mark) ?? selectedRegion;
                              }
                            } catch (_) {}
                            update(() {
                              foundLabel = label.length > 80
                                  ? label.substring(0, 80)
                                  : label;
                              foundLatitude = point.latitude;
                              foundLongitude = point.longitude;
                              searching = false;
                            });
                          } catch (_) {
                            update(() {
                              searching = false;
                              validation =
                                  'Nie znaleziono miejscowości. Dopisz powiat lub województwo.';
                            });
                          }
                        },
                  icon: searching
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.travel_explore),
                  label: const Text('Znajdź'),
                ),
                if (foundLabel != null) ...[
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.location_on_outlined),
                    title: Text(foundLabel!),
                    subtitle: Text(selectedRegion == null ? 'Wybierz województwo' : regions[selectedRegion] ?? selectedRegion!),
                  ),
                ],
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: ValueKey(selectedRegion),
                  initialValue: selectedRegion,
                  decoration: const InputDecoration(
                    labelText: 'Województwo',
                    border: OutlineInputBorder(),
                  ),
                  items: regions.entries
                      .where((e) => e.key != 'PL')
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      update(() => selectedRegion = value);
                    }
                  },
                ),
                if (validation != null) ...[
                  const SizedBox(height: 8),
                  Text(validation!),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Anuluj'),
            ),
            FilledButton(
              onPressed:
                  foundLabel == null ||
                      foundLatitude == null ||
                      foundLongitude == null ||
                      selectedRegion == null
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('Ustaw lokalizację'),
            ),
          ],
        ),
      ),
    );

    if (saved == true &&
        foundLabel != null &&
        foundLatitude != null &&
        foundLongitude != null) {
      ++generation;
      await widget.repository.setPrimaryLocation(
        label: foundLabel!,
        latitude: foundLatitude!,
        longitude: foundLongitude!,
        regionId: selectedRegion!,
      );
      if (!mounted) return;
      setState(() {
        region = selectedRegion!;
        localityLabel = foundLabel;
        localityAround = null;
        snapshot = widget.repository.cached(selectedRegion!);
        offlinePackageData = null;
        online = false;
        loading = false;
        error = null;
        loadSeen();
      });
      await loadOffline();
      if (widget.pushManager != null) {
        unawaited(widget.pushManager!.syncCurrentPreferences());
      }
      if (widget.repository.api.isNotEmpty) unawaited(startupSync());
    }

    queryController.dispose();
  }

  Future<void> changeRegion(String value) async {
    ++generation;
    await widget.repository.setRegion(value);
    if (widget.pushManager != null) {
      unawaited(widget.pushManager!.syncCurrentPreferences());
    }
    if (!mounted) return;
    setState(() {
      region = value;
      snapshot = widget.repository.cached(value);
      offlinePackageData = null;
      online = false;
      loading = false;
      error = null;
      loadSeen();
    });
    await loadOffline();
    if (widget.repository.api.isNotEmpty) unawaited(startupSync());
  }

  List<SafetyEvent> get events => snapshot?.alertEvents ?? [];
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        ['Status', 'Mapa', 'Alerty', 'Schronienia', 'Pomoc'][page],
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
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
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: chooseLocality,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 7,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on_outlined, size: 22),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  localityLabel ?? 'Wybierz miasto lub wieś',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  regions[region] ?? region,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.expand_more),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Odśwież dane',
                  onPressed:
                      loading || backgroundSync || widget.repository.api.isEmpty
                      ? null
                      : startupSync,
                  icon: loading || backgroundSync
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
          dataStateStrip(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: notice(error!, Icons.cloud_off),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: startupSync,
              child: ListView(
                key: PageStorageKey<int>(page),
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
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
      padding: const EdgeInsets.all(16),
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
  Widget dataStateStrip() {
    final now = DateTime.now();
    final nationalFresh =
        online && (snapshot?.freshAt(now, national: true) ?? false);
    final localFresh =
        online && (snapshot?.freshAt(now, national: false) ?? false);
    final hasOffline = !online && offlinePackageData != null;
    final hasAnyData = snapshot != null || offlinePackageData != null;
    final label = backgroundSync
        ? 'Synchronizacja danych…'
        : nationalFresh && localFresh
        ? 'Dane aktualne'
        : hasOffline
        ? 'Offline • ostatnia zapisana kopia'
        : hasAnyData
        ? 'Dane mogą być nieaktualne'
        : 'Brak pobranych danych';
    final icon = backgroundSync
        ? Icons.sync
        : nationalFresh && localFresh
        ? Icons.cloud_done_outlined
        : hasOffline
        ? Icons.offline_pin_outlined
        : hasAnyData
        ? Icons.schedule_outlined
        : Icons.cloud_off_outlined;
    final timestamp = hasOffline
        ? offlinePackageData!.snapshotTimestamp.toIso8601String()
        : snapshot?.data['serverTime'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Icon(icon, size: 19),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  timestamp == null ? label : '$label • ${stamp(timestamp)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (backgroundSync)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget statusOverviewCard() {
    final now = DateTime.now();
    final nationalFresh =
        online && (snapshot?.freshAt(now, national: true) ?? false);
    final regionalFresh =
        online && (snapshot?.freshAt(now, national: false) ?? false);
    final national = snapshot?.data['nationalStatus'];
    final regional = snapshot?.data['status'];

    String statusText(dynamic status, bool fresh) {
      if (status is! Map) return 'Brak danych';
      if (fresh) return status['displayText']?.toString() ?? 'Brak danych';
      if (!online && offlinePackageData != null) {
        return 'Ostatnia zapisana kopia: ${status['displayText'] ?? 'brak oceny'}';
      }
      return 'Dane nie są aktualne';
    }

    Widget row({
      required IconData icon,
      required String title,
      required String value,
      String? subtitle,
    }) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    final nearbyActive =
        localityAround?.nearbyEvents.where((item) {
          final lifecycle = item.event.data['lifecycle']?.toString();
          final validTo = DateTime.tryParse(
            item.event.data['validTo']?.toString() ?? '',
          );
          return lifecycle == 'ACTIVE' &&
              (validTo == null || validTo.isAfter(DateTime.now()));
        }).length ??
        0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            row(
              icon: Icons.public_outlined,
              title: 'Polska',
              value: statusText(national, nationalFresh),
            ),
            const Divider(height: 1),
            row(
              icon: Icons.map_outlined,
              title: regions[region] ?? region,
              value: statusText(regional, regionalFresh),
            ),
            if (localityLabel != null) ...[
              const Divider(height: 1),
              row(
                icon: Icons.near_me_outlined,
                title: localityLabel!,
                value: localityAround == null
                    ? 'Dane okolicy jeszcze niepobrane'
                    : nearbyActive == 0
                    ? 'Brak aktywnych komunikatów z dokładną lokalizacją w promieniu 20 km'
                    : nearbyActive == 1
                    ? '1 aktywny komunikat w promieniu 20 km'
                    : '$nearbyActive aktywne komunikaty w promieniu 20 km',
                subtitle:
                    'Komunikaty bez dokładnej geometrii są nadal uwzględniane na poziomie województwa.',
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> statusPage() {
    final changed = events
        .where((e) => e.revision > (seen[e.id] ?? 0))
        .toList();
    final active = events.where((e) {
      if (e.data['lifecycle']?.toString() != 'ACTIVE') return false;
      final validTo = DateTime.tryParse(e.data['validTo']?.toString() ?? '');
      return validTo == null || validTo.isAfter(DateTime.now());
    }).toList();
    final noData = snapshot == null && offlinePackageData == null;
    if (noData) {
      return [
        if (widget.repository.api.isEmpty)
          notice(
            'Brak połączenia z serwerem danych. Ten build testowy nie ma ustawionego adresu API.',
            Icons.cloud_off_outlined,
          )
        else
          empty(
            backgroundSync ? 'Pobieram dane' : 'Nie udało się pobrać danych',
            backgroundSync
                ? 'Pierwsza synchronizacja zapisze dane na telefonie, żeby aplikacja mogła działać także bez internetu.'
                : 'Sprawdź internet i przeciągnij ekran w dół, aby spróbować ponownie.',
            backgroundSync ? Icons.sync : Icons.cloud_off_outlined,
          ),
        heading('Po synchronizacji'),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.notifications_active_outlined),
          title: Text('Alerty i status regionu'),
        ),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.map_outlined),
          title: Text('Mapa zdarzeń i schronienia'),
        ),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.offline_pin_outlined),
          title: Text('Kopia offline na telefonie'),
        ),
      ];
    }

    return [
      if (!online && offlinePackageData != null)
        notice(
          'OFFLINE • LAST KNOWN GOOD z ${stamp(offlinePackageData!.snapshotTimestamp.toIso8601String())}. Wiek pakietu: ${formatOfflineAge(offlinePackageData!.createdAt, DateTime.now().toUtc())}. Stan źródeł pochodzi z chwili snapshotu. Brak nowych danych nie oznacza bezpieczeństwa.',
          Icons.offline_pin_outlined,
        ),
      statusOverviewCard(),
      heading('Najważniejsze aktywne komunikaty'),
      if (active.isEmpty)
        empty(
          'Brak aktywnych komunikatów w pobranych danych',
          'To nie jest potwierdzenie braku zagrożeń. Sprawdź też aktualność źródeł powyżej.',
          Icons.notifications_none_outlined,
        ),
      ...active.take(3).map(eventCard),
      Card(
        child: ListTile(
          leading: const Icon(Icons.timeline_outlined),
          title: const Text('NEPTUN • historyczny przebieg'),
          subtitle: const Text(
            'Zakończone ślady OSINT, timeline i źródła. Bez aktywnych dokładnych pozycji.',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => NeptunScreen(
                repository: widget.repository,
                openSource: openLink,
              ),
            ),
          ),
        ),
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
              builder: (_) => WatchedLocationsScreen(
                repository: widget.repository,
                onPreferencesChanged:
                    widget.pushManager?.syncCurrentPreferences,
              ),
            ),
          ),
        ),
      ),
      RadiationPanel(snapshot: snapshot, online: online, openSource: openLink),
      SecurityLevelsPanel(
        snapshot: snapshot,
        online: online,
        openSource: openLink,
      ),
      if (events.any(isImgwEvent)) ...[
        heading('Ostrzeżenia IMGW'),
        notice(
          'Źródłem pochodzenia danych jest Instytut Meteorologii i Gospodarki Wodnej – Państwowy Instytut Badawczy. Dane Instytutu Meteorologii i Gospodarki Wodnej – Państwowego Instytutu Badawczego zostały przetworzone.',
          Icons.cloud_outlined,
        ),
        ...events.where(isImgwEvent).take(5).map(eventCard),
      ],
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
        'Każdy komunikat zachowuje źródło i czas pobrania. Brak nowych danych nie jest traktowany jako potwierdzenie bezpieczeństwa.',
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
          label: const Text('Sprawdź stan wszystkich źródeł'),
        ),
      heading('Zapisane komunikaty regionu'),
      ...events.take(30).map(eventCard),
    ];
  }

  String verificationLabel(SafetyEvent event) =>
      switch (event.data['verification']?.toString()) {
        'CONFIRMED' => 'POTWIERDZONE',
        'PROBABLE' => 'PRAWDOPODOBNE',
        'UNVERIFIED' => 'NIEZWERYFIKOWANE',
        'REFUTED' => 'ZDEMENTOWANE',
        'DISPUTED' => 'SPRZECZNE INFORMACJE',
        _ => 'WERYFIKACJA NIEUSTALONA',
      };

  String severityLabel(SafetyEvent event) =>
      switch (event.data['severity']?.toString()) {
        'CRITICAL' => 'KRYTYCZNE',
        'HIGH' || 'SEVERE' => 'WYSOKIE',
        'ELEVATED' || 'MODERATE' => 'PODWYŻSZONE',
        'NORMAL' || 'LOW' => 'STANDARDOWE',
        _ => 'POZIOM NIEUSTALONY',
      };

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
                badge(verificationLabel(e)),
                badge(severityLabel(e)),
                badge(e.provenance),
                if (e.sources.length > 1)
                  badge('POŁĄCZONE ŹRÓDŁA: ${e.sources.length}'),
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

  bool isImgwEvent(SafetyEvent e) =>
      e.sources.any((s) => s['id'] == 'IMGW_METEO' || s['id'] == 'IMGW_HYDRO');

  String sourceLabel(String value) => switch (value) {
    'POLICE' => 'Policja',
    'PSP_INCIDENTS' => 'PSP',
    'CSIRT_GOV' => 'CSIRT GOV',
    'IMGW_METEO' => 'IMGW meteo',
    'IMGW_HYDRO' => 'IMGW hydro',
    _ => value,
  };

  List<Widget> rcbPage() {
    final sourceOptions = <String>{
      'Wszystkie',
      'RCB',
      'RSO',
      'WCZK',
      'IMGW_METEO',
      'IMGW_HYDRO',
      'PAA',
      'CERT',
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
    ShelterMap(
      radiation: snapshot?.data['radiation'],
      radiationOnline: online,
      events: events,
      watchedLocations: widget.repository.watchedLocations,
      openEvent: details,
      key: ValueKey(
        'map:${widget.repository.api}:$region:${widget.repository.dataGeneration}:${widget.repository.watchedLocations.length}',
      ),
      repository: widget.repository,
      region: region,
      ukraine: false,
      openLink: openLink,
    ),
    const SizedBox(height: 8),
    const Text(
      'Dotknij punktu po szczegóły. Warstwy, schronienia i PAA zmienisz przyciskiem na mapie. GPS działa tylko po Twoim kliknięciu.',
    ),
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
      'Konto jest niewymagane. GPS jest używany wyłącznie po wyraźnej akcji użytkownika; aplikacja nie zapisuje historii ruchu ani nie śledzi pozycji w tle. Region, ustawienia, cache i pakiety offline pozostają na urządzeniu. Przy ręcznym „Wokół mnie” serwer może otrzymać jednorazowo współrzędne potrzebne do obliczenia odległości. Zapisane miejsca są wysyłane do backendu tylko po osobnym włączeniu kategorii powiadomień „Obserwowane lokalizacje”; po jej wyłączeniu backend otrzymuje pustą listę, a po wyrejestrowaniu push dane lokalizacji urządzenia są usuwane z rekordu push. Przy fallbacku offline obliczenia są lokalne. Linki otwierają zewnętrzną przeglądarkę.',
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
            padding: const EdgeInsets.all(16),
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
                    child: const Text(
                      'Usuń lekki cache (pakiety offline bez zmian)',
                    ),
                  ),
                  ListTile(
                    title: const Text('Dane offline'),
                    subtitle: const Text(
                      'Pobierz, odśwież lub usuń pakiety regionów',
                    ),
                    leading: const Icon(Icons.offline_pin_outlined),
                    onTap: () {
                      Navigator.pop(sheet);
                      Navigator.of(context)
                          .push(
                            MaterialPageRoute<void>(
                              builder: (_) => OfflineDataScreen(
                                repository: widget.repository,
                              ),
                            ),
                          )
                          .then((_) => loadOffline());
                    },
                  ),
                  if (widget.pushManager != null)
                    ListTile(
                      title: const Text('Powiadomienia'),
                      subtitle: Text(
                        widget.pushManager!.state.registered
                            ? 'Urządzenie zarejestrowane'
                            : 'Zarządzaj zgodą i kategoriami alertów',
                      ),
                      leading: const Icon(Icons.notifications_outlined),
                      onTap: () {
                        Navigator.pop(sheet);
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => NotificationSettingsScreen(
                              manager: widget.pushManager!,
                            ),
                          ),
                        );
                      },
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
                    '$appVersion • Pakiety offline • Push opt-in • GPS tylko na żądanie',
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
