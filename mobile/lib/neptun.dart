import 'dart:async';
import 'dart:math' show Point;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'map_interaction.dart';
import 'model.dart';

class NeptunData {
  final Map<String, dynamic> data;
  NeptunData._(this.data);

  factory NeptunData.parse(dynamic input) {
    if (input is! Map) throw const FormatException('Niepoprawne dane NEPTUN');
    final m = Map<String, dynamic>.from(input);
    final delay = m['safetyDelayHours'],
        minimum = m['minimumPublishedPrecisionKm'];
    if (m['schemaVersion'] != 2 ||
        m['mode'] != 'LIVE_AND_HISTORY' ||
        delay is! num ||
        delay < 24 ||
        minimum is! num ||
        minimum < 10 ||
        m['tracks'] is! List ||
        (m['tracks'] as List).length > 500 ||
        m['map'] is! Map ||
        m['map']['type'] != 'FeatureCollection' ||
        m['map']['features'] is! List ||
        m['live'] is! Map) {
      throw const FormatException('Nieobsługiwany kontrakt NEPTUN');
    }
    final server = DateTime.parse(m['serverTime'] as String);
    final cutoff = server.subtract(Duration(hours: delay.toInt()));
    final live = Map<String, dynamic>.from(m['live'] as Map);
    for (final key in [
      'lastSuccessfulSyncAt',
      'sourceServerTime',
      'validUntil',
    ]) {
      final value = live[key];
      if (value != null && value is! String) {
        throw const FormatException('Niepoprawny czas live NEPTUN');
      }
      if (value is String) DateTime.parse(value);
    }
    if (!{
          'LIVE',
          'STALE',
          'DOWN',
          'NOT_CONFIGURED',
          'UNAVAILABLE',
        }.contains(live['state']) ||
        live['sourceUrl'] is! String ||
        Uri.tryParse(live['sourceUrl'] as String)?.scheme != 'https' ||
        live['threats'] is! List ||
        (live['threats'] as List).length > 5000 ||
        live['map'] is! Map ||
        live['map']['type'] != 'FeatureCollection' ||
        live['map']['features'] is! List) {
      throw const FormatException('Niepoprawny live NEPTUN');
    }
    final liveIds = <String>{};
    for (final raw in live['threats'] as List) {
      if (raw is! Map) {
        throw const FormatException('Niepoprawne zagrożenie NEPTUN');
      }
      final t = Map<String, dynamic>.from(raw);
      if (t['id'] is! String ||
          !liveIds.add(t['id'] as String) ||
          ![
            'uav',
            'fpv',
            'recon',
            'missile',
            'ballistic',
            'kab',
            'mig31k',
            'unknown',
          ].contains(t['type']) ||
          t['title'] !=
              const {
                'uav': 'BSP / dron',
                'fpv': 'FPV / dron',
                'recon': 'Obiekt rozpoznawczy',
                'missile': 'Rakieta',
                'ballistic': 'Zagrożenie balistyczne',
                'kab': 'Kierowana bomba lotnicza',
                'mig31k': 'MiG-31K',
                'unknown': 'Nieokreślone zagrożenie',
              }[t['type']] ||
          !['low', 'medium', 'high'].contains(t['confidenceLevel']) ||
          !['active', 'stale'].contains(t['status']) ||
          t['updatedAt'] is! String ||
          t.containsKey('heading') ||
          t.containsKey('velocity') ||
          t.containsKey('confirmedAt') ||
          t.containsKey('positionQuality') ||
          t.containsKey('explanationShort') ||
          t.containsKey('locality') ||
          t.containsKey('district') ||
          t.containsKey('trail') ||
          t.containsKey('lifecycle') ||
          t.containsKey('displayConfidence') ||
          t.containsKey('presumptiveCourse') ||
          t.containsKey('destination') ||
          t.containsKey('sea') ||
          t.containsKey('regionKey')) {
        throw const FormatException('Niepoprawny live NEPTUN');
      }
      DateTime.parse(t['updatedAt'] as String);
      final lat = t['latitude'],
          lon = t['longitude'],
          precision = t['precisionKm'];
      final areaOnly = t['areaOnly'] == true;
      if ((lat == null) != (lon == null) ||
          (lat == null) != (precision == null) ||
          (lat != null &&
              (lat is! num ||
                  lon is! num ||
                  precision is! num ||
                  !lat.isFinite ||
                  !lon.isFinite ||
                  !precision.isFinite ||
                  lat.abs() > 90 ||
                  lon.abs() > 180 ||
                  precision < minimum)) ||
          (areaOnly && (lat != null || lon != null))) {
        throw const FormatException('Zbyt dokładna lub błędna pozycja NEPTUN');
      }
    }
    for (final rawFeature in live['map']['features'] as List) {
      if (rawFeature is! Map ||
          rawFeature['geometry'] is! Map ||
          rawFeature['geometry']['type'] != 'Point' ||
          rawFeature['geometry']['coordinates'] is! List ||
          (rawFeature['geometry']['coordinates'] as List).length != 2 ||
          rawFeature['properties'] is! Map ||
          rawFeature['properties']['live'] != true ||
          rawFeature['properties']['coarse'] != true ||
          rawFeature['properties'].containsKey('heading') ||
          rawFeature['properties'].containsKey('velocity') ||
          rawFeature['properties'].containsKey('prediction') ||
          rawFeature['properties'].containsKey('locality') ||
          rawFeature['properties'].containsKey('district') ||
          rawFeature['properties'].containsKey('explanationShort') ||
          rawFeature['properties'].containsKey('trail') ||
          rawFeature['properties'].containsKey('presumptiveCourse') ||
          rawFeature['properties'].containsKey('destination') ||
          !liveIds.contains(rawFeature['properties']['threatId'])) {
        throw const FormatException('Niepoprawna mapa live NEPTUN');
      }
    }

    final ids = <String>{};
    for (final raw in m['tracks'] as List) {
      if (raw is! Map) throw const FormatException('Niepoprawny ślad NEPTUN');
      final t = Map<String, dynamic>.from(raw);
      if (t['id'] is! String ||
          !(t['id'] as String).startsWith('NEPTUN-') ||
          !ids.add(t['id'] as String) ||
          t['title'] is! String ||
          t['description'] is! String ||
          t['lifecycle'] != 'ENDED' ||
          ![
            'CONFIRMED',
            'PROBABLE',
            'UNVERIFIED',
            'REFUTED',
            'DISPUTED',
          ].contains(t['verification']) ||
          t['endedAt'] is! String ||
          t['observations'] is! List ||
          (t['observations'] as List).isEmpty ||
          (t['observations'] as List).length > 100) {
        throw const FormatException('Niepoprawny ślad NEPTUN');
      }
      final ended = DateTime.parse(t['endedAt'] as String);
      if (ended.isAfter(cutoff)) {
        throw const FormatException('Ślad NEPTUN nie jest historyczny');
      }
      if (t['startedAt'] != null) {
        final started = DateTime.parse(t['startedAt'] as String);
        if (started.isAfter(ended)) {
          throw const FormatException('Niepoprawny czas śladu');
        }
      }
      DateTime? previous;
      for (final rawObservation in t['observations'] as List) {
        if (rawObservation is! Map) {
          throw const FormatException('Niepoprawna obserwacja NEPTUN');
        }
        final o = Map<String, dynamic>.from(rawObservation);
        if (o['observedAt'] is! String) {
          throw const FormatException('Brak czasu obserwacji NEPTUN');
        }
        final observed = DateTime.parse(o['observedAt'] as String);
        if (previous != null && observed.isBefore(previous)) {
          throw const FormatException('Niechronologiczne obserwacje NEPTUN');
        }
        if (observed.isAfter(ended)) {
          throw const FormatException('Obserwacja po zakończeniu śladu');
        }
        previous = observed;
        final lat = o['latitude'],
            lon = o['longitude'],
            precision = o['precisionKm'];
        final hasCoordinates = lat != null || lon != null;
        if ((lat == null) != (lon == null) ||
            (hasCoordinates && precision == null) ||
            (!hasCoordinates && precision != null) ||
            (lat != null && (lat is! num || !lat.isFinite || lat.abs() > 90)) ||
            (lon != null &&
                (lon is! num || !lon.isFinite || lon.abs() > 180)) ||
            (precision != null &&
                (precision is! num ||
                    !precision.isFinite ||
                    precision < minimum))) {
          throw const FormatException(
            'Zbyt dokładna lub błędna geometria NEPTUN',
          );
        }
        final source = o['source'];
        if (source is! Map ||
            source['id'] is! String ||
            source['name'] is! String ||
            source['url'] is! String ||
            source['origin'] is! String) {
          throw const FormatException('Brak pochodzenia obserwacji NEPTUN');
        }
      }
    }
    for (final rawFeature in m['map']['features'] as List) {
      if (rawFeature is! Map ||
          rawFeature['geometry'] is! Map ||
          rawFeature['geometry']['type'] != 'LineString' ||
          rawFeature['geometry']['coordinates'] is! List ||
          (rawFeature['geometry']['coordinates'] as List).length < 2 ||
          rawFeature['properties'] is! Map ||
          rawFeature['properties']['historicalOnly'] != true ||
          !ids.contains(rawFeature['properties']['trackId'])) {
        throw const FormatException('Niepoprawna mapa NEPTUN');
      }
      for (final p in rawFeature['geometry']['coordinates'] as List) {
        if (p is! List ||
            p.length != 2 ||
            p[0] is! num ||
            p[1] is! num ||
            !(p[0] as num).isFinite ||
            !(p[1] as num).isFinite ||
            (p[0] as num).abs() > 180 ||
            (p[1] as num).abs() > 90) {
          throw const FormatException('Niepoprawny punkt mapy NEPTUN');
        }
      }
    }
    return NeptunData._(m);
  }

  Map<String, dynamic> get live =>
      Map<String, dynamic>.from(data['live'] as Map);
  List<Map<String, dynamic>> get liveThreats => (live['threats'] as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  List<Map<String, dynamic>> get tracks => (data['tracks'] as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  bool isFreshLive(DateTime now) {
    if (live['state'] != 'LIVE') return false;
    final sync = DateTime.tryParse(
      live['lastSuccessfulSyncAt']?.toString() ?? '',
    );
    final validUntil = DateTime.tryParse(live['validUntil']?.toString() ?? '');
    if (sync == null || validUntil == null) return false;
    if (sync.isAfter(now.add(const Duration(seconds: 30)))) return false;
    return validUntil.isAfter(now);
  }
}

String neptunTypeLabel(String value) => switch (value) {
  'uav' => 'BSP / dron',
  'fpv' => 'FPV / dron',
  'recon' => 'Rozpoznanie',
  'missile' => 'Rakieta',
  'ballistic' => 'Balistyka',
  'kab' => 'KAB',
  'mig31k' => 'MiG-31K',
  _ => 'Nieokreślone',
};

Map<String, dynamic>? neptunThreatForFeature(NeptunData data, dynamic feature) {
  if (feature is! Map || feature['properties'] is! Map) return null;
  final id = feature['properties']['threatId'];
  if (id is! String || id.isEmpty) return null;
  for (final threat in data.liveThreats) {
    if (threat['id'] == id) return threat;
  }
  return null;
}

class NeptunScreen extends StatefulWidget {
  final DataRepository repository;
  final void Function(String) openSource;
  final bool showMap;
  const NeptunScreen({
    super.key,
    required this.repository,
    required this.openSource,
    this.showMap = true,
  });

  @override
  State<NeptunScreen> createState() => _NeptunScreenState();
}

class _NeptunScreenState extends State<NeptunScreen> {
  NeptunData? snapshot;
  bool loading = false, online = false, refreshing = false;
  String? error;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    snapshot = widget.repository.cachedNeptun();
    if (widget.repository.api.isNotEmpty) unawaited(refresh());
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && widget.repository.api.isNotEmpty) {
        unawaited(refresh(silent: true));
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> refresh({bool silent = false}) async {
    if (refreshing) return;
    refreshing = true;
    if (!silent) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final result = await widget.repository.refreshNeptun();
      if (!mounted) return;
      setState(() {
        snapshot = result;
        online = true;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        online = false;
        error = apiFailureMessage(e);
      });
    } finally {
      refreshing = false;
      if (!silent && mounted) setState(() => loading = false);
    }
  }

  String when(dynamic value) => value is String ? stamp(value) : 'Nie podano';

  String typeLabel(String value) => neptunTypeLabel(value);

  Widget liveCard(Map<String, dynamic> t, {required bool current}) {
    final location = (t['region'] as String?)?.trim() ?? '';
    final precision = t['precisionKm'];
    return Card(
      child: ListTile(
        leading: Icon(t['advisory'] == true ? Icons.info_outline : Icons.radar),
        title: Text(t['title'] as String),
        subtitle: Text(
          '${typeLabel(t['type'] as String)}'
          '${location.isEmpty ? '' : ' • $location'}\n'
          '${t['advisory'] == true
              ? 'Obserwacja informacyjna'
              : current
              ? 'Aktywne zagrożenie w feedzie NEPTUN'
              : 'Ostatnio pobrany wpis NEPTUN'}'
          ' • aktualizacja ${when(t['updatedAt'])}'
          '${precision == null ? '' : ' • pozycja zgrubna ≥ $precision km'}',
        ),
        isThreeLine: true,
      ),
    );
  }

  Widget trackCard(Map<String, dynamic> t) {
    final observations = (t['observations'] as List).cast<Map>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Chip(label: Text(t['verification'] as String)),
                const Chip(label: Text('ZAKOŃCZONY')),
                Chip(label: Text(t['objectType'] as String)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              t['title'] as String,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if ((t['description'] as String).isNotEmpty)
              Text(t['description'] as String),
            const SizedBox(height: 8),
            Text('Przebieg: ${t['directionText'] ?? 'Nie ustalono'}'),
            Text('Początek: ${when(t['startedAt'])}'),
            Text('Zakończenie: ${when(t['endedAt'])}'),
            Text('Obserwacje: ${observations.length}'),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Timeline i źródła'),
              children: [
                for (final o in observations)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${when(o['observedAt'])} • ${o['locationText'] ?? 'Obszar nieustalony'}',
                    ),
                    subtitle: Text(
                      '${o['verification']} • dokładność publikowana: ${o['precisionKm'] == null ? 'brak geometrii' : '≥ ${o['precisionKm']} km'}'
                      '${o['correction'] == null ? '' : '\nKorekta: ${o['correction']}'}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Otwórz źródło',
                      onPressed: () =>
                          widget.openSource(o['source']['url'] as String),
                      icon: const Icon(Icons.open_in_new),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final threats = snapshot?.liveThreats ?? const <Map<String, dynamic>>[];
    final tracks = snapshot?.tracks ?? const <Map<String, dynamic>>[];
    final liveState = snapshot?.live['state']?.toString() ?? 'UNAVAILABLE';
    final isLive =
        online &&
        snapshot != null &&
        snapshot!.isFreshLive(DateTime.now().toUtc());
    return Scaffold(
      appBar: AppBar(
        title: const Text('NEPTUN'),
        actions: [
          IconButton(
            onPressed: loading || widget.repository.api.isEmpty
                ? null
                : refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Odśwież NEPTUN',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: Icon(
                  isLive ? Icons.wifi_tethering : Icons.schedule_outlined,
                ),
                title: Text(
                  isLive
                      ? 'LIVE • ${threats.length} aktywnych wpisów'
                      : snapshot == null
                      ? 'BRAK DANYCH BIEŻĄCYCH'
                      : '$liveState • ostatnia poprawna kopia',
                ),
                subtitle: Text(
                  snapshot == null
                      ? 'Nie pobrano jeszcze poprawnej kopii NEPTUN.'
                      : 'Ostatnia udana synchronizacja: ${when(snapshot?.live['lastSuccessfulSyncAt'])}',
                ),
              ),
            ),
            if (loading) const LinearProgressIndicator(),
            if (error != null) Text(error!),
            if (widget.showMap && snapshot != null) NeptunMap(data: snapshot!),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => widget.openSource('https://neptun.in.ua/'),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Dane live: NEPTUN • neptun.in.ua'),
            ),
            const Text(
              'NEPTUN jest agregatorem informacyjnym, nie oficjalnym systemem alarmowym. Pozycje w tej aplikacji są celowo zgrubne; nie pokazujemy kursu, prędkości ani predykcji ruchu.',
            ),
            const SizedBox(height: 12),
            Text(
              isLive ? 'Bieżące zagrożenia' : 'Ostatnio pobrane zagrożenia',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (threats.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Brak bieżących wpisów w ostatniej pobranej kopii NEPTUN. Nie oznacza to braku zagrożenia — kieruj się oficjalnymi alarmami.',
                  ),
                ),
              ),
            ...threats.map((threat) => liveCard(threat, current: isLive)),
            const SizedBox(height: 16),
            Text(
              'Historia zweryfikowana',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Text(
              'Zakończone ślady są publikowane osobno, po opóźnieniu bezpieczeństwa.',
            ),
            if (tracks.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Brak opublikowanych śladów historycznych.'),
              ),
            ...tracks.map(trackCard),
          ],
        ),
      ),
    );
  }
}

class NeptunMap extends StatefulWidget {
  final NeptunData data;
  const NeptunMap({super.key, required this.data});

  @override
  State<NeptunMap> createState() => _NeptunMapState();
}

class _NeptunMapState extends State<NeptunMap> {
  MapLibreMapController? controller;
  String? error;
  bool ready = false;
  bool cameraMoving = false;
  bool syncInProgress = false;
  bool syncPending = false;

  @override
  void dispose() {
    ready = false;
    controller = null;
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant NeptunMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (ready && oldWidget.data.data != widget.data.data) {
      if (cameraMoving || syncInProgress) {
        syncPending = true;
      } else {
        unawaited(syncSources());
      }
    }
  }

  void cameraMove(CameraPosition _) {
    cameraMoving = true;
  }

  void cameraIdle() {
    cameraMoving = false;
    if (syncPending) {
      syncPending = false;
      unawaited(syncSources());
    }
  }

  Future<void> syncSources() async {
    final c = controller;
    if (!ready || c == null) return;
    if (cameraMoving || syncInProgress) {
      syncPending = true;
      return;
    }
    syncInProgress = true;
    final data = widget.data;
    try {
      await c.setGeoJsonSource('neptun-live', data.live['map']);
      await c.setGeoJsonSource('neptun-history', data.data['map']);
      if (mounted) {
        setState(() {
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          error = 'Nie udało się odświeżyć warstwy NEPTUN.';
        });
      }
    } finally {
      syncInProgress = false;
      if (mounted && syncPending && !cameraMoving) {
        syncPending = false;
        unawaited(syncSources());
      }
    }
  }

  String confidenceLabel(dynamic value) => switch (value) {
    'high' => 'wysoka',
    'medium' => 'średnia',
    'low' => 'niska',
    _ => 'nieokreślona',
  };

  Future<void> handleMapTap(Point<double> point, LatLng _) async {
    final c = controller;
    if (!ready || c == null || !mounted) return;
    try {
      final features = await c.queryRenderedFeatures(point, const [
        'neptun-live-points',
      ], null);
      if (!mounted || features.isEmpty) return;
      final threat = neptunThreatForFeature(widget.data, features.first);
      if (threat == null) return;
      final location = (threat['region'] as String?)?.trim() ?? '';
      final precision = threat['precisionKm'];
      final sourceCount = threat['sourceCount'];
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.radar),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        threat['title'] as String,
                        style: Theme.of(sheetContext).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text('Typ: ${neptunTypeLabel(threat['type'] as String)}'),
                if (location.isNotEmpty) Text('Obszar: $location'),
                Text(
                  'Status: ${threat['status'] == 'active' ? 'aktywny' : 'nieaktualny / STALE'}',
                ),
                Text('Aktualizacja: ${stamp(threat['updatedAt'] as String)}'),
                Text(
                  'Pewność: ${confidenceLabel(threat['confidenceLevel'])}'
                  '${sourceCount is num ? ' • źródła: $sourceCount' : ''}',
                ),
                if (precision is num)
                  Text('Pozycja celowo zgrubna: ≥ ${precision.toString()} km'),
                const SizedBox(height: 10),
                const Text(
                  'NEPTUN jest źródłem informacyjnym. Aplikacja nie pokazuje kursu, prędkości ani predykcji ruchu.',
                ),
              ],
            ),
          ),
        ),
      );
    } catch (_) {
      // A tap must never break map interaction if the style is reloading.
    }
  }

  Future<void> styled() async {
    if (!mounted) return;
    final c = controller;
    if (c == null) return;
    try {
      await c.addSource(
        'neptun-live',
        GeojsonSourceProperties(data: widget.data.live['map']),
      );
      await c.addCircleLayer(
        'neptun-live',
        'neptun-live-points',
        const CircleLayerProperties(
          circleColor: '#c62828',
          circleRadius: 8,
          circleStrokeColor: '#ffffff',
          circleStrokeWidth: 2,
        ),
      );
      await c.addSource(
        'neptun-history',
        GeojsonSourceProperties(data: widget.data.data['map']),
      );
      await c.addLineLayer(
        'neptun-history',
        'neptun-history-lines',
        const LineLayerProperties(
          lineColor: '#7062c8',
          lineWidth: 3,
          lineOpacity: 0.55,
        ),
      );
      ready = true;
    } catch (_) {
      if (mounted) {
        setState(() {
          error = 'Warstwa NEPTUN nie może zostać wyświetlona.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(
        height: 380,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: MapLibreMap(
            gestureRecognizers: mapGestureRecognizers(),
            styleString: const String.fromEnvironment(
              'MAP_STYLE_URL',
              defaultValue: 'https://tiles.openfreemap.org/styles/liberty',
            ),
            initialCameraPosition: const CameraPosition(
              target: LatLng(49, 31),
              zoom: 5,
            ),
            onMapCreated: (c) {
              if (mounted) controller = c;
            },
            onStyleLoadedCallback: styled,
            onCameraMove: cameraMove,
            onCameraIdle: cameraIdle,
            onMapClick: (point, coordinates) =>
                unawaited(handleMapTap(point, coordinates)),
            featureTapsTriggersMapClick: true,
          ),
        ),
      ),
      const SizedBox(height: 6),
      const Text(
        'Czerwone punkty: bieżące, celowo zgrubne pozycje. Fioletowe linie: wyłącznie historia.',
      ),
      if (error != null) Text(error!),
    ],
  );
}
