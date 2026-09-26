import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'model.dart';
import 'event_details.dart';
import 'source_status.dart';
import 'push_notifications.dart';
import 'offline_packages.dart';
import 'offline_repository.dart';
import 'offline_data_screen.dart';
import 'build_config.dart';
import 'app_version.dart';
import 'screens/dashboard_screen.dart';
import 'screens/alerts_screen.dart';
import 'screens/map_screen.dart';
import 'screens/more_screen.dart';
import 'ui/app_theme.dart';

String? localityRegionSeed(String currentRegion) =>
    currentRegion == 'PL' ? null : currentRegion;

Future<void> main() async {
  validateBuildConfiguration();
  WidgetsFlutterBinding.ensureInitialized();
  final repository = DataRepository(await SharedPreferences.getInstance());
  final pushAdapter = await safePushPlatformAdapter(
    FirebasePushPlatformAdapter.fromBuildConfiguration,
  );
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
    theme: buildSafetyTheme(Brightness.light),
    darkTheme: buildSafetyTheme(Brightness.dark),
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
  final Set<int> visitedPages = <int>{0};
  bool online = false, loading = false, backgroundSync = false;
  late String region;
  String? localityLabel;
  Snapshot? snapshot;
  AroundResult? localityAround;
  OfflineRegionPackage? offlinePackageData;
  String? error;
  Timer? timer, refreshTimer;
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
    var queryText = '';
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
                  autofocus: true,
                  onChanged: (value) => queryText = value,
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
                          final query = queryText.trim();
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
                    subtitle: Text(
                      selectedRegion == null
                          ? 'Wybierz województwo'
                          : regions[selectedRegion] ?? selectedRegion!,
                    ),
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
  }

  List<SafetyEvent> get events => snapshot?.alertEvents ?? [];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(['Bezpieczna Polska', 'Mapa', 'Alerty', 'Więcej'][page]),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: IconButton.filledTonal(
            tooltip: 'Ustawienia',
            onPressed: settings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ),
      ],
    ),
    body: SafeArea(
      child: IndexedStack(
        index: page,
        children: [
          DashboardScreen(
            snapshot: snapshot,
            events: events,
            localityAround: localityAround,
            offlinePackage: offlinePackageData,
            online: online,
            loading: loading,
            backgroundSync: backgroundSync,
            region: region,
            localityLabel: localityLabel,
            error: error,
            onRefresh: startupSync,
            onChooseLocality: chooseLocality,
            onOpenAlerts: () => _selectPage(2),
            onOpenEvent: details,
          ),
          visitedPages.contains(1)
              ? SafetyMapScreen(
                  repository: widget.repository,
                  snapshot: snapshot,
                  events: events,
                  online: online,
                  region: region,
                  onOpenEvent: details,
                  openLink: openLink,
                )
              : const SizedBox.shrink(),
          visitedPages.contains(2)
              ? AlertsScreen(
                  events: events,
                  onOpenEvent: details,
                  onRefresh: startupSync,
                )
              : const SizedBox.shrink(),
          visitedPages.contains(3)
              ? MoreScreen(
                  repository: widget.repository,
                  snapshot: snapshot,
                  online: online,
                  region: region,
                  openLink: openLink,
                  call112: call112,
                  onWatchedLocationsChanged:
                      widget.pushManager?.syncCurrentPreferences,
                )
              : const SizedBox.shrink(),
        ],
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: page,
      onDestinationSelected: _selectPage,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.shield_outlined),
          selectedIcon: Icon(Icons.shield),
          label: 'Start',
        ),
        NavigationDestination(
          icon: Icon(Icons.map_outlined),
          selectedIcon: Icon(Icons.map),
          label: 'Mapa',
        ),
        NavigationDestination(
          icon: Icon(Icons.campaign_outlined),
          selectedIcon: Icon(Icons.campaign),
          label: 'Alerty',
        ),
        NavigationDestination(
          icon: Icon(Icons.more_horiz),
          selectedIcon: Icon(Icons.more),
          label: 'Więcej',
        ),
      ],
    ),
  );

  void _selectPage(int index) {
    if (index == page && visitedPages.contains(index)) return;
    setState(() {
      visitedPages.add(index);
      page = index;
    });
  }

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
                  ListTile(
                    title: const Text('Diagnostyka źródeł'),
                    subtitle: const Text(
                      'Stan synchronizacji i szczegóły techniczne',
                    ),
                    leading: const Icon(Icons.hub_outlined),
                    onTap: () {
                      Navigator.pop(sheet);
                      openSources();
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
    var apiValue = widget.repository.developerApi;
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
                TextFormField(
                  initialValue: apiValue,
                  onChanged: (value) => apiValue = value,
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
                  await widget.repository.setDeveloperApi(apiValue);
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
