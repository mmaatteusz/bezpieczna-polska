import 'radiation.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'map_interaction.dart';
import 'map_layers.dart';
import 'model.dart';
import 'shelters.dart';

class _MapLegend extends StatelessWidget {
  final bool showAlerts;
  final bool showImgw;
  final bool showShelters;
  final bool showWatched;
  final bool showRadiation;

  const _MapLegend({
    required this.showAlerts,
    required this.showImgw,
    required this.showShelters,
    required this.showWatched,
    required this.showRadiation,
  });

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      if (showAlerts)
        const _MapLegendItem(
          color: Color(0xffb3261e),
          label: 'Alerty i komunikaty',
        ),
      if (showImgw)
        const _MapLegendItem(
          color: Color(0xff1565c0),
          label: 'Ostrzeżenia IMGW',
        ),
      if (showShelters)
        const _MapLegendItem(
          color: Color(0xff2e7d32),
          label: 'Punkty schronienia',
        ),
      if (showWatched)
        const _MapLegendItem(
          color: Color(0xffef6c00),
          label: 'Obserwowane miejsca',
        ),
      if (showRadiation)
        const _MapLegendItem(
          color: Color(0xff7563b8),
          label: 'Pomiary promieniowania PAA',
        ),
    ];
    if (items.isEmpty) return const SizedBox.shrink();

    return Material(
      key: const ValueKey('map-legend'),
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 14,
          runSpacing: 6,
          children: items,
        ),
      ),
    );
  }
}

class _MapLegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _MapLegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}

class ShelterMap extends StatefulWidget {
  final DataRepository repository;
  final String region;
  final bool ukraine;
  final Map<String, dynamic>? radiation;
  final bool radiationOnline;
  final List<SafetyEvent> events;
  final List<WatchedLocation> watchedLocations;
  final void Function(SafetyEvent) openEvent;
  final void Function(String) openLink;
  const ShelterMap({
    super.key,
    this.radiation,
    this.radiationOnline = false,
    required this.events,
    required this.watchedLocations,
    required this.openEvent,
    required this.repository,
    required this.region,
    required this.ukraine,
    required this.openLink,
  });
  @override
  State<ShelterMap> createState() => _ShelterMapState();
}

class _ShelterMapState extends State<ShelterMap> {
  MapLibreMapController? controller;
  Timer? debounce, clock, styleFallback, onlineRetry;
  bool showRadiation = false, locating = false;
  bool showEvents = true, showImgw = true, showWatched = true;
  bool showGpsInterference = false, gpsInterferenceLoading = false;
  bool legendAlertsVisible = false, legendImgwVisible = false;
  bool legendSheltersVisible = false, legendWatchedVisible = false;
  bool legendRadiationVisible = false;
  bool ready = false, loading = false, online = false, fallbackStyle = false;
  bool overviewMode = false, nationalEventsLoading = false;
  bool radiationRefreshRunning = false, radiationOverrideOnline = false;
  int ticket = 0, gpsInterferenceTicket = 0;
  String availability = 'ALL', message = 'Przygotowywanie mapy…';
  String? gpsInterferenceError;
  MapViewport? viewport;
  GpsInterferenceViewport? gpsInterference;
  MapRequest? renderedRequest;
  Snapshot? nationalSnapshot;
  DateTime? nationalEventsUpdatedAt, radiationLastFetch;
  Map<String, dynamic>? radiationOverride;
  Map<String, List<double>> administrativeAnchors = const {};
  ShelterMapProvider get provider => ShelterMapProvider(widget.repository);
  GpsInterferenceProvider get gpsInterferenceProvider =>
      GpsInterferenceProvider(widget.repository);
  Map<String, dynamic>? get currentRadiation =>
      radiationOverride ?? widget.radiation;
  bool get currentRadiationOnline => radiationOverride != null
      ? radiationOverrideOnline
      : widget.radiationOnline;

  bool get currentRadiationHasPoints {
    final raw = currentRadiation;
    if (raw == null) return false;
    try {
      return (RadiationData.parse(raw).data['measurements'] as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  List<SafetyEvent> get contextEvents => overviewMode
      ? (widget.region == 'PL'
            ? widget.events
            : nationalSnapshot?.alertEvents ?? widget.events)
      : widget.events;

  List<double>? visibleLegendBbox;

  List<Map<String, dynamic>> contextEventFeatures(DateTime now) =>
      markMapRcbCounts(
        markMapCategoryCollisions(
          contextEvents
              .where(
                (event) => mapEventVisibleForLayers(
                  event,
                  showEvents: showEvents,
                  showImgw: showImgw,
                ),
              )
              .expand(
                (event) => mapEventFeatures(
                  event,
                  now,
                  administrativeAnchors: administrativeAnchors,
                ),
              )
              .toList(),
        ),
      );

  bool featureInsideBbox(Map<String, dynamic> feature, List<double> bbox) {
    final geometry = feature['geometry'];
    if (geometry is! Map || geometry['type'] != 'Point') return false;
    final coordinates = geometry['coordinates'];
    if (coordinates is! List || coordinates.length != 2) return false;
    final lon = coordinates[0], lat = coordinates[1];
    if (lon is! num || lat is! num) return false;
    return lon >= bbox[0] && lon <= bbox[2] && lat >= bbox[1] && lat <= bbox[3];
  }

  String? featurePointKey(Map feature) {
    final geometry = feature['geometry'];
    if (geometry is! Map || geometry['type'] != 'Point') return null;
    final coordinates = geometry['coordinates'];
    if (coordinates is! List || coordinates.length != 2) return null;
    final lon = coordinates[0], lat = coordinates[1];
    if (lon is! num || lat is! num) return null;
    return '${lon.toDouble().toStringAsFixed(6)}:'
        '${lat.toDouble().toStringAsFixed(6)}';
  }

  bool viewportHasSheltersInBbox(MapViewport? value, List<double> bbox) {
    final features = value?.data['features'];
    if (features is! List) return false;
    return features.whereType<Map>().any(
      (feature) => featureInsideBbox(Map<String, dynamic>.from(feature), bbox),
    );
  }

  Future<void> syncShelterAnnotations(MapViewport? value) async {
    final c = controller;
    if (c == null || !ready || widget.ukraine) return;

    await c.clearCircles();
    final rawFeatures = value?.data['features'];
    if (rawFeatures is! List || rawFeatures.isEmpty) return;

    final options = <CircleOptions>[];
    final data = <Map<String, dynamic>>[];
    for (final rawFeature in rawFeatures) {
      if (rawFeature is! Map) continue;
      final feature = Map<String, dynamic>.from(rawFeature);
      final geometry = feature['geometry'];
      final properties = feature['properties'];
      if (geometry is! Map || properties is! Map) continue;
      final coordinates = geometry['coordinates'];
      if (geometry['type'] != 'Point' ||
          coordinates is! List ||
          coordinates.length != 2 ||
          coordinates[0] is! num ||
          coordinates[1] is! num) {
        continue;
      }
      final p = Map<String, dynamic>.from(properties);
      final lon = (coordinates[0] as num).toDouble();
      final lat = (coordinates[1] as num).toDouble();
      final cluster = p['cluster'] == true;
      options.add(
        CircleOptions(
          geometry: LatLng(lat, lon),
          circleColor: cluster ? '#1b5e20' : '#2e7d32',
          circleRadius: cluster ? 19.0 : 7.0,
          circleOpacity: 0.96,
          circleStrokeColor: '#ffffff',
          circleStrokeWidth: cluster ? 2.0 : 1.5,
        ),
      );
      data.add({
        'kind': 'shelter-annotation',
        'properties': p,
        'coordinates': [lon, lat],
      });
    }
    if (options.isNotEmpty) {
      await c.addCircles(options, data);
    }
  }

  Future<void> openShelterData(
    Map<String, dynamic> properties,
    List<dynamic> coordinates,
  ) async {
    final c = controller;
    if (c == null || !mounted || coordinates.length != 2) return;
    final lon = coordinates[0], lat = coordinates[1];
    if (lon is! num || lat is! num) return;

    if (properties['cluster'] == true) {
      final expansionZoom = properties['expansionZoom'];
      if (expansionZoom is num) {
        await c.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(lat.toDouble(), lon.toDouble()),
            expansionZoom.toDouble(),
          ),
        );
      }
      return;
    }

    final shelter = ShelterPoint.parse(properties);
    final navigationUrl = shelterNavigationUrl(
      latitude: (shelter.data['latitude'] as num).toDouble(),
      longitude: (shelter.data['longitude'] as num).toDouble(),
    );
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                shelter.address,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                '${properties['municipality']} • ${properties['county']}',
              ),
              Text(shelter.availability),
              const Text(
                'Punkt schronienia wg PSP. Klasa ochrony, pojemność i bieżący dostęp nie są potwierdzone.',
              ),
              Text('Data danych: ${properties['dataDate']}'),
              if (!online || viewport?.freshAt(DateTime.now()) != true)
                const Text(
                  'Ostatnie zapisane dane — aktualność niepotwierdzona',
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.openLink(navigationUrl);
                  },
                  icon: const Icon(Icons.navigation_outlined),
                  label: const Text('Nawiguj do schronu'),
                ),
              ),
              TextButton(
                onPressed: () => widget.openLink(
                  'https://dane.gov.pl/pl/dataset/28058,punkty-schronienia-w-polsce',
                ),
                child: const Text('Źródło: KG PSP / dane.gov.pl'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> openShelterCircle(Circle circle) async {
    final raw = circle.data;
    if (raw == null || raw['kind'] != 'shelter-annotation') return;
    final properties = raw['properties'];
    final coordinates = raw['coordinates'];
    if (properties is! Map || coordinates is! List) return;
    await openShelterData(
      Map<String, dynamic>.from(properties),
      List<dynamic>.from(coordinates),
    );
  }

  void updateMapLegend(
    List<double> bbox, {
    bool? sheltersVisible,
    bool? radiationVisible,
  }) {
    final eventFeatures = contextEventFeatures(DateTime.now());
    bool categoryVisible(String category) => eventFeatures.any((feature) {
      if (!featureInsideBbox(feature, bbox)) return false;
      final properties = feature['properties'];
      return properties is Map && properties['mapCategory'] == category;
    });
    final watchedVisible =
        showWatched &&
        widget.watchedLocations.any(
          (location) =>
              location.longitude >= bbox[0] &&
              location.longitude <= bbox[2] &&
              location.latitude >= bbox[1] &&
              location.latitude <= bbox[3],
        );
    final nextAlerts = showEvents && categoryVisible('ALERT');
    final nextImgw = showImgw && categoryVisible('IMGW');
    final nextShelters = sheltersVisible ?? legendSheltersVisible;
    final nextRadiation = showRadiation
        ? (radiationVisible ?? legendRadiationVisible)
        : false;
    final nextBbox = List<double>.from(bbox);
    if (!mounted) return;
    if (legendAlertsVisible == nextAlerts &&
        legendImgwVisible == nextImgw &&
        legendSheltersVisible == nextShelters &&
        legendWatchedVisible == watchedVisible &&
        legendRadiationVisible == nextRadiation) {
      visibleLegendBbox = nextBbox;
      return;
    }
    setState(() {
      visibleLegendBbox = nextBbox;
      legendAlertsVisible = nextAlerts;
      legendImgwVisible = nextImgw;
      legendSheltersVisible = nextShelters;
      legendWatchedVisible = watchedVisible;
      legendRadiationVisible = nextRadiation;
    });
  }

  LatLng get homeTarget {
    final lat = widget.repository.primaryLocationLatitude;
    final lon = widget.repository.primaryLocationLongitude;
    return lat != null && lon != null
        ? LatLng(lat, lon)
        : const LatLng(52.1, 19.4);
  }

  double get homeZoom =>
      widget.repository.primaryLocationLatitude != null ? 10.5 : 5.2;

  static const empty = {'type': 'FeatureCollection', 'features': <dynamic>[]};
  static const onlineStyle = String.fromEnvironment(
    'MAP_STYLE_URL',
    defaultValue: 'https://tiles.openfreemap.org/styles/liberty',
  );
  static const offlineStyle =
      '{"version":8,"name":"Bezpieczna Polska offline","sources":{},"layers":[{"id":"offline-background","type":"background","paint":{"background-color":"#e9ecef"}}]}';
  @override
  void initState() {
    super.initState();
    if (widget.region != 'PL') {
      nationalSnapshot = widget.repository.cached('PL');
    }
    clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (showRadiation) {
        unawaited(refreshRadiationSnapshot());
      }
      if (overviewMode) {
        unawaited(refresh());
      } else {
        unawaited(syncContextLayers());
      }
    });
  }

  @override
  void didUpdateWidget(covariant ShelterMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.radiation != widget.radiation) {
      radiationOverride = null;
      radiationOverrideOnline = false;
      radiationLastFetch = null;
    }
    if (showRadiation &&
        (oldWidget.radiation != widget.radiation ||
            oldWidget.radiationOnline != widget.radiationOnline)) {
      idle();
    }
    if (oldWidget.events != widget.events ||
        oldWidget.watchedLocations != widget.watchedLocations) {
      unawaited(syncContextLayers());
    }
    if (oldWidget.region != widget.region) {
      nationalSnapshot = widget.region == 'PL'
          ? null
          : widget.repository.cached('PL');
      nationalEventsUpdatedAt = null;
      idle();
    }
  }

  Future<void> refreshRadiationSnapshot({bool force = false}) async {
    if (!mounted || !showRadiation || radiationRefreshRunning) return;
    final now = DateTime.now();
    final retryAfter = currentRadiationHasPoints
        ? const Duration(minutes: 5)
        : const Duration(minutes: 1);
    if (!force &&
        radiationLastFetch != null &&
        now.difference(radiationLastFetch!) < retryAfter) {
      return;
    }
    radiationRefreshRunning = true;
    radiationLastFetch = now;
    try {
      final snapshot = await widget.repository.refresh(widget.region);
      final raw = snapshot.data['radiation'];
      if (raw is! Map) throw const FormatException('Brak danych PAA');
      final normalized = Map<String, dynamic>.from(raw);
      RadiationData.parse(normalized);
      if (!mounted) return;
      setState(() {
        radiationOverride = normalized;
        radiationOverrideOnline = true;
      });
    } catch (_) {
      if (mounted && radiationOverride != null) {
        setState(() => radiationOverrideOnline = false);
      }
    } finally {
      radiationRefreshRunning = false;
      if (mounted) unawaited(refresh());
    }
  }

  @override
  void dispose() {
    ticket++;
    ready = false;
    controller = null;
    debounce?.cancel();
    clock?.cancel();
    styleFallback?.cancel();
    onlineRetry?.cancel();
    super.dispose();
  }

  void armStyleFallback(MapLibreMapController c) {
    styleFallback?.cancel();
    styleFallback = Timer(const Duration(seconds: 4), () async {
      if (!mounted || ready || controller != c) return;
      try {
        fallbackStyle = true;
        await c.setStyle(offlineStyle);
        if (mounted) {
          setState(
            () => message =
                'OFFLINE MAPA • podkład sieciowy nie odpowiedział. Uruchomiono lokalne płótno dla zapisanych overlayów.',
          );
        }
      } catch (_) {
        if (mounted) {
          setState(
            () => message =
                'Nie udało się uruchomić ani podkładu online, ani lokalnego płótna mapy.',
          );
        }
      }
    });
  }

  Future<void> retryOnlineStyle() async {
    final c = controller;
    if (c == null) return;
    setState(() {
      ready = false;
      fallbackStyle = false;
      message = 'Ładowanie podkładu online…';
    });
    armStyleFallback(c);
    try {
      await c.setStyle(onlineStyle);
    } catch (_) {
      // Timer above switches to the local style without claiming live map data.
    }
  }

  Future<void> styled() async {
    if (!mounted) return;
    final c = controller;
    if (c == null) return;
    styleFallback?.cancel();
    try {
      if (!widget.ukraine) {
        final voivodeships =
            jsonDecode(
                  await rootBundle.loadString(
                    'assets/poland_voivodeships_min.geojson',
                  ),
                )
                as Map<String, dynamic>;
        try {
          final rawAnchors =
              jsonDecode(
                    await rootBundle.loadString(
                      'assets/poland_powiat_centroids.json',
                    ),
                  )
                  as Map<String, dynamic>;
          final rawPowiaty = rawAnchors['powiaty'];
          if (rawAnchors['schemaVersion'] != 2 || rawPowiaty is! Map) {
            throw const FormatException('Niepoprawne centroidy TERYT');
          }
          final parsed = <String, List<double>>{};
          for (final entry in rawPowiaty.entries) {
            final coordinates = entry.value;
            if (entry.key is! String ||
                !RegExp(r'^\d{4}$').hasMatch(entry.key as String) ||
                coordinates is! List ||
                coordinates.length != 2 ||
                coordinates.any((value) => value is! num)) {
              throw const FormatException('Niepoprawny punkt TERYT');
            }
            parsed[entry.key as String] = [
              (coordinates[0] as num).toDouble(),
              (coordinates[1] as num).toDouble(),
            ];
          }
          if (parsed.length < 300) {
            throw const FormatException('Niepełny zestaw centroidów TERYT');
          }
          administrativeAnchors = parsed;
        } catch (_) {
          // Map remains usable; a missing local helper must not break live data.
          administrativeAnchors = const {};
        }
        await c.addSource(
          'voivodeships',
          GeojsonSourceProperties(data: voivodeships),
        );
        await c.addLineLayer(
          'voivodeships',
          'voivodeship-borders',
          const LineLayerProperties(
            lineColor: '#5f6b73',
            lineWidth: 1.0,
            lineOpacity: 0.30,
          ),
        );
      }
      await c.addSource(
        'gps-interference',
        GeojsonSourceProperties(data: empty),
      );
      await c.addFillLayer(
        'gps-interference',
        'gps-interference-fill',
        const FillLayerProperties(
          fillColor: [
            'match',
            ['get', 'level'],
            'HIGH',
            '#e53935',
            'MEDIUM',
            '#fdd835',
            '#43a047',
          ],
          fillOpacity: 0.42,
          fillOutlineColor: '#455a64',
        ),
      );
      await c.addSource('radiation', GeojsonSourceProperties(data: empty));
      await c.addCircleLayer(
        'radiation',
        'radiation-points',
        const CircleLayerProperties(circleColor: '#7563b8', circleRadius: 7),
      );
      await c.addSource('shelters', GeojsonSourceProperties(data: empty));
      // Shelter circles are rendered through MapLibre's annotation manager.
      // This avoids Android style-layer/source refresh issues observed after
      // panning far away from the user's selected/home location. The GeoJSON
      // source remains for cluster count labels and as a validated data mirror.
      await c.addSymbolLayer(
        'shelters',
        'shelter-counts',
        const SymbolLayerProperties(
          textField: [
            'to-string',
            ['get', 'point_count'],
          ],
          textSize: 12,
          textColor: '#ffffff',
          textAllowOverlap: true,
        ),
        filter: [
          '==',
          ['get', 'cluster'],
          true,
        ],
      );
      await c.addSource('events', GeojsonSourceProperties(data: empty));
      await c.addCircleLayer(
        'events',
        'event-alert-points',
        const CircleLayerProperties(
          circleColor: '#b3261e',
          circleRadius: 8,
          circleStrokeColor: '#ffffff',
          circleStrokeWidth: 2,
        ),
        filter: [
          'all',
          [
            '==',
            ['get', 'mapCategory'],
            'ALERT',
          ],
          [
            '==',
            ['get', 'mapCollision'],
            false,
          ],
        ],
      );
      await c.addCircleLayer(
        'events',
        'event-imgw-points',
        const CircleLayerProperties(
          circleColor: '#1565c0',
          circleRadius: 8,
          circleStrokeColor: '#ffffff',
          circleStrokeWidth: 2,
        ),
        filter: [
          'all',
          [
            '==',
            ['get', 'mapCategory'],
            'IMGW',
          ],
          [
            '==',
            ['get', 'mapCollision'],
            false,
          ],
        ],
      );
      await c.addCircleLayer(
        'events',
        'event-alert-collision-points',
        const CircleLayerProperties(
          circleColor: '#b3261e',
          circleRadius: 8,
          circleStrokeColor: '#ffffff',
          circleStrokeWidth: 2,
          circleTranslate: [-9.0, 0.0],
        ),
        filter: [
          'all',
          [
            '==',
            ['get', 'mapCategory'],
            'ALERT',
          ],
          [
            '==',
            ['get', 'mapCollision'],
            true,
          ],
        ],
      );
      await c.addCircleLayer(
        'events',
        'event-imgw-collision-points',
        const CircleLayerProperties(
          circleColor: '#1565c0',
          circleRadius: 8,
          circleStrokeColor: '#ffffff',
          circleStrokeWidth: 2,
          circleTranslate: [9.0, 0.0],
        ),
        filter: [
          'all',
          [
            '==',
            ['get', 'mapCategory'],
            'IMGW',
          ],
          [
            '==',
            ['get', 'mapCollision'],
            true,
          ],
        ],
      );
      await c.addSymbolLayer(
        'events',
        'event-rcb-counts',
        const SymbolLayerProperties(
          textField: [
            'to-string',
            ['get', 'mapRcbCount'],
          ],
          textSize: 11,
          textColor: '#ffffff',
          textAllowOverlap: true,
          textIgnorePlacement: true,
        ),
        filter: [
          'all',
          [
            '==',
            ['get', 'mapIsRcb'],
            true,
          ],
          [
            '>',
            ['get', 'mapRcbCount'],
            1,
          ],
          [
            '==',
            ['get', 'mapRcbCountLeader'],
            true,
          ],
          [
            '==',
            ['get', 'mapCollision'],
            false,
          ],
        ],
      );
      await c.addSymbolLayer(
        'events',
        'event-rcb-collision-counts',
        const SymbolLayerProperties(
          textField: [
            'to-string',
            ['get', 'mapRcbCount'],
          ],
          textSize: 11,
          textColor: '#ffffff',
          textTranslate: [-9.0, 0.0],
          textAllowOverlap: true,
          textIgnorePlacement: true,
        ),
        filter: [
          'all',
          [
            '==',
            ['get', 'mapIsRcb'],
            true,
          ],
          [
            '>',
            ['get', 'mapRcbCount'],
            1,
          ],
          [
            '==',
            ['get', 'mapRcbCountLeader'],
            true,
          ],
          [
            '==',
            ['get', 'mapCollision'],
            true,
          ],
        ],
      );
      await c.addSource('watched', GeojsonSourceProperties(data: empty));
      await c.addCircleLayer(
        'watched',
        'watched-points',
        const CircleLayerProperties(
          circleColor: '#ef6c00',
          circleRadius: 7,
          circleStrokeColor: '#ffffff',
          circleStrokeWidth: 2,
        ),
      );
      await c.addSource('user-location', GeojsonSourceProperties(data: empty));
      await c.addCircleLayer(
        'user-location',
        'user-location-point',
        const CircleLayerProperties(
          circleColor: '#37474f',
          circleRadius: 8,
          circleStrokeColor: '#ffffff',
          circleStrokeWidth: 3,
        ),
      );
      if (!mounted) return;
      ready = true;
      await syncContextLayers();
      await refresh();
    } catch (_) {
      if (mounted) {
        setState(() => message = 'Nie udało się uruchomić warstwy mapy');
      }
    }
  }

  void idle() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 350), refresh);
  }

  void scheduleOnlineRetry() {
    onlineRetry?.cancel();
    if (!mounted || widget.ukraine || !ready) return;
    onlineRetry = Timer(const Duration(seconds: 15), () {
      if (!mounted || !ready || loading || online || widget.ukraine) {
        return;
      }
      unawaited(refresh());
    });
  }

  Future<void> refreshNationalEvents() async {
    if (widget.region == 'PL' ||
        widget.repository.api.isEmpty ||
        nationalEventsLoading) {
      return;
    }
    final now = DateTime.now();
    if (nationalEventsUpdatedAt != null &&
        now.difference(nationalEventsUpdatedAt!) < const Duration(minutes: 1)) {
      return;
    }
    nationalEventsLoading = true;
    try {
      nationalSnapshot = await widget.repository.refresh('PL');
    } catch (_) {
      nationalSnapshot ??= widget.repository.cached('PL');
    } finally {
      nationalEventsUpdatedAt = DateTime.now();
      nationalEventsLoading = false;
    }
  }

  Future<void> syncContextLayers() async {
    final c = controller;
    if (!ready || c == null || widget.ukraine) return;

    final eventFeatures = contextEventFeatures(DateTime.now());
    final watchedFeatures = showWatched
        ? widget.watchedLocations
              .map(
                (location) => {
                  'type': 'Feature',
                  'geometry': {
                    'type': 'Point',
                    'coordinates': [location.longitude, location.latitude],
                  },
                  'properties': {
                    'locationId': location.id,
                    'label': location.label,
                  },
                },
              )
              .toList()
        : <Map<String, dynamic>>[];

    await c.setGeoJsonSource('events', {
      'type': 'FeatureCollection',
      'features': eventFeatures,
    });
    await c.setGeoJsonSource('watched', {
      'type': 'FeatureCollection',
      'features': watchedFeatures,
    });
    final bbox = visibleLegendBbox;
    if (bbox != null) {
      updateMapLegend(bbox);
    }
  }

  Future<void> refreshGpsInterferenceForCurrentViewport() async {
    final c = controller;
    if (!ready || c == null || widget.ukraine || !showGpsInterference) return;
    final bounds = await c.getVisibleRegion();
    final west = bounds.southwest.longitude.clamp(-180, 180).toDouble();
    final east = bounds.northeast.longitude.clamp(-180, 180).toDouble();
    final south = bounds.southwest.latitude.clamp(-85, 85).toDouble();
    final north = bounds.northeast.latitude.clamp(-85, 85).toDouble();
    if (west >= east || south >= north) return;
    await refreshGpsInterferenceForBounds([west, south, east, north]);
  }

  Future<void> refreshGpsInterferenceForBounds(List<double> bbox) async {
    final c = controller;
    if (!ready || c == null || widget.ukraine || !showGpsInterference) return;
    final current = ++gpsInterferenceTicket;
    if (mounted) {
      setState(() {
        gpsInterferenceLoading = true;
        gpsInterferenceError = null;
      });
    }
    try {
      final result = await gpsInterferenceProvider.fetch(bbox);
      if (!mounted ||
          current != gpsInterferenceTicket ||
          !showGpsInterference) {
        return;
      }
      await c.setGeoJsonSource('gps-interference', result.data);
      if (!mounted || current != gpsInterferenceTicket) return;
      setState(() {
        gpsInterference = result;
        gpsInterferenceError = null;
      });
    } catch (failure) {
      if (!mounted || current != gpsInterferenceTicket) return;
      if (gpsInterference == null) {
        await c.setGeoJsonSource('gps-interference', empty);
      }
      setState(() => gpsInterferenceError = apiFailureMessage(failure));
    } finally {
      if (mounted && current == gpsInterferenceTicket) {
        setState(() => gpsInterferenceLoading = false);
      }
    }
  }

  Future<void> setGpsInterferenceVisible(bool value) async {
    setState(() {
      showGpsInterference = value;
      gpsInterferenceError = null;
    });
    if (!value) {
      gpsInterferenceTicket++;
      gpsInterference = null;
      gpsInterferenceLoading = false;
      await controller?.setGeoJsonSource('gps-interference', empty);
      return;
    }
    await refreshGpsInterferenceForCurrentViewport();
  }

  Future<void> refresh() async {
    final c = controller;
    if (!ready || c == null || widget.ukraine) return;
    final current = ++ticket;
    setState(() => loading = true);
    MapRequest? request;
    try {
      final bounds = await c.getVisibleRegion();
      if (!mounted || current != ticket) return;
      final west = bounds.southwest.longitude.clamp(-180, 180).toDouble(),
          east = bounds.northeast.longitude.clamp(-180, 180).toDouble();
      final south = bounds.southwest.latitude.clamp(-85, 85).toDouble(),
          north = bounds.northeast.latitude.clamp(-85, 85).toDouble();
      if (west >= east || south >= north) {
        throw const FormatException('Obszar poza zakresem');
      }
      final bbox = <double>[west, south, east, north];
      updateMapLegend(bbox);
      if (showGpsInterference) {
        unawaited(refreshGpsInterferenceForBounds([west, south, east, north]));
      }
      if (showRadiation) {
        try {
          final data = currentRadiation == null
              ? null
              : RadiationData.parse(currentRadiation);
          final items = (data?.data['measurements'] as List? ?? []).cast<Map>();
          final visible = items
              .where(
                (p) =>
                    p['latitude'] is num &&
                    p['longitude'] is num &&
                    p['longitude'] >= west &&
                    p['longitude'] <= east &&
                    p['latitude'] >= south &&
                    p['latitude'] <= north,
              )
              .toList();
          await c.setGeoJsonSource('radiation', {
            'type': 'FeatureCollection',
            'features': visible
                .map(
                  (p) => {
                    'type': 'Feature',
                    'geometry': {
                      'type': 'Point',
                      'coordinates': [p['longitude'], p['latitude']],
                    },
                    'properties': Map<String, dynamic>.from(p),
                  },
                )
                .toList(),
          });
          updateMapLegend(bbox, radiationVisible: visible.isNotEmpty);
        } catch (_) {
          // A broken PAA payload must never break shelters/events on the map.
          await c.setGeoJsonSource('radiation', empty);
          updateMapLegend(bbox, radiationVisible: false);
        }
      } else {
        await c.setGeoJsonSource('radiation', empty);
        updateMapLegend(bbox, radiationVisible: false);
      }
      final zoom = (c.cameraPosition?.zoom ?? 5).clamp(0, 22).toDouble();
      updateMapLegend(
        bbox,
        sheltersVisible:
            mapShowsShelters(zoom) && viewportHasSheltersInBbox(viewport, bbox),
      );
      if (!mapShowsShelters(zoom)) {
        if (!overviewMode) {
          setState(() => overviewMode = true);
        }
        onlineRetry?.cancel();
        await c.setGeoJsonSource('shelters', empty);
        await c.clearCircles();
        viewport = null;
        renderedRequest = null;
        await refreshNationalEvents();
        await syncContextLayers();
        updateMapLegend(bbox, sheltersVisible: false);
        if (!mounted || current != ticket) return;
        setState(() {
          message =
              'Widok Polski: Punkty schronienia są ukryte przy tym oddaleniu. Czerwone punkty oznaczają Alerty i komunikaty, a niebieskie Ostrzeżenia IMGW. Zdarzenie bez dokładnej lokalizacji jest oznaczone symbolicznie dla właściwego województwa.';
        });
        return;
      }
      if (overviewMode) {
        setState(() => overviewMode = false);
      }
      await syncContextLayers();
      request = shelterViewportRequest(
        [west, south, east, north],
        zoom,
        availability,
      );
      // Keep the previous viewport during ordinary pan/zoom so markers do not
      // blink out while the replacement request is in flight. A changed
      // region/filter is a different dataset and must be cleared immediately.
      if (mapDatasetChanged(renderedRequest, request)) {
        viewport = null;
        renderedRequest = null;
        await c.setGeoJsonSource('shelters', empty);
        await c.clearCircles();
        updateMapLegend(bbox, sheltersVisible: false);
      }
      final result = await provider.fetch(request);
      if (!mounted || current != ticket) return;
      await c.setGeoJsonSource('shelters', result.data);
      await syncShelterAnnotations(result);
      if (!mounted || current != ticket) return;
      updateMapLegend(
        bbox,
        sheltersVisible: viewportHasSheltersInBbox(result, bbox),
      );
      onlineRetry?.cancel();
      setState(() {
        viewport = result;
        renderedRequest = request;
        online = true;
        message = result.freshAt(DateTime.now())
            ? ''
            : 'Połączono z serwerem, ale źródłowy wykaz schronień jest oznaczony jako STALE.';
      });
    } catch (failure) {
      if (!mounted || current != ticket) return;
      final cached = request == null ? null : provider.cached(request);
      MapViewport? offline;
      MapRequest? fallbackRequest = request;
      if (cached == null && request != null) {
        offline = await provider.offline(request);
        if (offline == null && widget.region != 'PL') {
          final regionalRequest = MapRequest(
            request.bbox,
            request.zoom,
            widget.region,
            request.availability,
          );
          offline = await provider.offline(regionalRequest);
          if (offline != null) fallbackRequest = regionalRequest;
        }
      }
      final fallback = cached ?? offline;
      if (fallback != null) {
        await c.setGeoJsonSource('shelters', fallback.data);
        await syncShelterAnnotations(fallback);
      } else {
        // The previous viewport is no longer valid for the new camera area.
        await c.setGeoJsonSource('shelters', empty);
        await c.clearCircles();
      }
      if (!mounted || current != ticket) return;
      final bbox = visibleLegendBbox;
      if (bbox != null) {
        updateMapLegend(
          bbox,
          sheltersVisible: viewportHasSheltersInBbox(fallback, bbox),
        );
      }
      setState(() {
        viewport = fallback;
        renderedRequest = fallback == null ? null : fallbackRequest;
        online = false;
        message = fallback == null
            ? apiFailureMessage(failure)
            : offline != null
            ? 'OFFLINE • lokalny overlay schronień z pakietu z ${stamp(offline.metadata['offlinePackageTimestamp'])}. Podkład bazowy OpenFreeMap nie jest częścią pakietu i może być niedostępny. Brak nowych danych nie oznacza bezpieczeństwa.'
            : 'Pokazano zapisaną kopię viewportu. ${apiFailureMessage(failure)}';
      });
      scheduleOnlineRetry();
    } finally {
      if (mounted && current == ticket) setState(() => loading = false);
    }
  }

  Future<String?> chooseEventCategory({
    required List<SafetyEvent> alerts,
    required List<SafetyEvent> imgw,
  }) {
    if (!mounted) return Future.value(null);
    return showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Co chcesz otworzyć?',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              const Text('W tym miejscu nakładają się różne typy informacji.'),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: Color(0xffb3261e),
                  child: Icon(Icons.notifications_active_outlined),
                ),
                title: const Text('Zdarzenia i komunikaty'),
                subtitle: Text(
                  alerts.length == 1 ? '1 pozycja' : '${alerts.length} pozycji',
                ),
                onTap: () => Navigator.of(sheetContext).pop('ALERT'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: Color(0xff1565c0),
                  child: Icon(Icons.cloud_outlined),
                ),
                title: const Text('Ostrzeżenia IMGW'),
                subtitle: Text(
                  imgw.length == 1 ? '1 pozycja' : '${imgw.length} pozycji',
                ),
                onTap: () => Navigator.of(sheetContext).pop('IMGW'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> showEventChoice(
    List<SafetyEvent> events, {
    required String title,
    required Color color,
  }) async {
    if (!mounted || events.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 4),
              const Text('Wybierz konkretną pozycję do otwarcia.'),
              const SizedBox(height: 12),
              for (final event in events)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  title: Text(event.title),
                  subtitle: Text(
                    mapEventIsImgw(event)
                        ? 'Ostrzeżenie IMGW'
                        : event.isRcb
                        ? 'Alert RCB'
                        : 'Alert lub komunikat',
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    widget.openEvent(event);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> tapped(math.Point<double> point, LatLng location) async {
    final c = controller;
    if (c == null || !ready) return;
    try {
      if (showRadiation) {
        final points = await c.queryRenderedFeatures(point, [
          'radiation-points',
        ], null);
        if (points.isNotEmpty && mounted) {
          final p = (points.first as Map)['properties'] as Map;
          final data = currentRadiation == null
              ? null
              : RadiationData.parse(currentRadiation);
          await showModalBottomSheet<void>(
            context: context,
            builder: (_) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  '${p['name']}\n${p['value']} ${p['unit']}\nPomiar: ${stamp(p['measuredAt'])}\n${data?.measurementText(DateTime.now(), currentRadiationOnline) ?? 'STALE'}\nPomiar nie jest alarmem.',
                ),
              ),
            ),
          );
          return;
        }
      }
      if (showGpsInterference) {
        final gpsHits = await c.queryRenderedFeatures(point, [
          'gps-interference-fill',
        ], null);
        if (gpsHits.isNotEmpty && mounted) {
          final properties = Map<String, dynamic>.from(
            (gpsHits.first as Map)['properties'] as Map,
          );
          await showModalBottomSheet<void>(
            context: context,
            builder: (context) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Zakłócenia GPS/GNSS',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text('Poziom: ${properties['level']}'),
                    Text('Obniżona dokładność: ${properties['percentBad']}%'),
                    Text(
                      'Samoloty: ${properties['goodAircraft']} prawidłowych / ${properties['badAircraft']} z obniżoną dokładnością',
                    ),
                    Text('Dzień: ${properties['date']} UTC'),
                    const SizedBox(height: 8),
                    const Text(
                      'To wskaźnik obniżonej dokładności nawigacji raportowanej przez statki powietrzne. Nie potwierdza przyczyny ani celowego zagłuszania.',
                    ),
                    TextButton(
                      onPressed: () =>
                          widget.openLink('https://gpsjam.org/faq'),
                      child: const Text('Źródło i metodologia: GPSJAM'),
                    ),
                  ],
                ),
              ),
            ),
          );
          return;
        }
      }
      final contextHits = await c.queryRenderedFeatures(point, [
        'event-alert-points',
        'event-imgw-points',
        'event-alert-collision-points',
        'event-imgw-collision-points',
        'watched-points',
      ], null);
      if (contextHits.isNotEmpty && mounted) {
        final hitEventIds = <String>{};
        final hitEventPoints = <String>{};
        String? locationId;
        for (final rawHit in contextHits) {
          if (rawHit is! Map || rawHit['properties'] is! Map) continue;
          final properties = Map<String, dynamic>.from(
            rawHit['properties'] as Map,
          );
          final eventId = properties['eventId']?.toString();
          if (eventId != null && eventId.isNotEmpty) {
            hitEventIds.add(eventId);
            final pointKey = featurePointKey(rawHit);
            if (pointKey != null) hitEventPoints.add(pointKey);
          }
          locationId ??= properties['locationId']?.toString();
        }

        // Red and blue collision markers are intentionally shifted on screen,
        // but still represent the same underlying map coordinate. If the user
        // taps either one, include every event anchored at that coordinate so
        // the first choice is always ALERT vs IMGW, never whichever circle
        // happened to win MapLibre hit-testing.
        if (hitEventPoints.isNotEmpty) {
          for (final feature in contextEventFeatures(DateTime.now())) {
            final pointKey = featurePointKey(feature);
            if (pointKey == null || !hitEventPoints.contains(pointKey)) {
              continue;
            }
            final properties = feature['properties'];
            if (properties is! Map) continue;
            final eventId = properties['eventId']?.toString();
            if (eventId != null && eventId.isNotEmpty) {
              hitEventIds.add(eventId);
            }
          }
        }

        final hitEvents = <SafetyEvent>[
          for (final event in contextEvents)
            if (hitEventIds.contains(event.id)) event,
        ];
        if (hitEvents.length == 1) {
          widget.openEvent(hitEvents.single);
          return;
        }
        if (hitEvents.length > 1) {
          final alerts = hitEvents
              .where((event) => !mapEventIsImgw(event))
              .toList();
          final imgw = hitEvents.where(mapEventIsImgw).toList();

          if (alerts.isNotEmpty && imgw.isNotEmpty) {
            final category = await chooseEventCategory(
              alerts: alerts,
              imgw: imgw,
            );
            if (!mounted || category == null) return;
            if (category == 'IMGW') {
              await showEventChoice(
                imgw,
                title: 'Ostrzeżenia IMGW',
                color: const Color(0xff1565c0),
              );
            } else {
              await showEventChoice(
                alerts,
                title: 'Zdarzenia i komunikaty',
                color: const Color(0xffb3261e),
              );
            }
            return;
          }

          final onlyImgw = imgw.isNotEmpty;
          await showEventChoice(
            onlyImgw ? imgw : alerts,
            title: onlyImgw ? 'Ostrzeżenia IMGW' : 'Zdarzenia i komunikaty',
            color: onlyImgw ? const Color(0xff1565c0) : const Color(0xffb3261e),
          );
          return;
        }

        if (locationId != null) {
          WatchedLocation? selected;
          for (final item in widget.watchedLocations) {
            if (item.id == locationId) {
              selected = item;
              break;
            }
          }
          if (selected != null) {
            final item = selected;
            await showModalBottomSheet<void>(
              context: context,
              builder: (context) => SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Promień alertów: ${item.radiusKm.toStringAsFixed(0)} km',
                      ),
                      if (item.regionId != null)
                        Text(
                          'Region: ${regions[item.regionId] ?? item.regionId}',
                        ),
                      const SizedBox(height: 8),
                      const Text(
                        'Obserwowane miejsce jest zapisane lokalnie. Aplikacja nie tworzy historii przemieszczania.',
                      ),
                    ],
                  ),
                ),
              ),
            );
            return;
          }
        }
      }
      return;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nie udało się odczytać punktu')),
        );
      }
    }
  }

  Future<void> locateUser() async {
    final c = controller;
    if (c == null || !ready) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mapa jeszcze się ładuje.')),
        );
      }
      return;
    }
    if (locating) return;
    setState(() => locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Lokalizacja w telefonie jest wyłączona. Włącz ją i spróbuj ponownie.',
              ),
            ),
          );
        }
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                permission == LocationPermission.deniedForever
                    ? 'Dostęp do lokalizacji jest zablokowany w ustawieniach systemu.'
                    : 'Bez zgody na lokalizację nie można pokazać Twojej pozycji.',
              ),
            ),
          );
        }
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      await c.setGeoJsonSource('user-location', {
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'geometry': {
              'type': 'Point',
              'coordinates': [position.longitude, position.latitude],
            },
            'properties': const {'kind': 'user-location'},
          },
        ],
      });
      await c.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(position.latitude, position.longitude),
          13,
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Pokazano bieżącą pozycję. Lokalizacja nie jest zapisywana.',
            ),
          ),
        );
      }
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Nie udało się ustalić lokalizacji na czas. Spróbuj ponownie.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nie udało się pobrać lokalizacji.')),
        );
      }
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  void zoom(double delta) {
    final c = controller, position = controller?.cameraPosition;
    if (c != null && position != null) {
      c.animateCamera(
        CameraUpdate.zoomTo((position.zoom + delta).clamp(0, 22).toDouble()),
      );
    }
  }

  Future<void> goHome() async {
    final c = controller;
    if (c == null) return;
    await c.animateCamera(CameraUpdate.newLatLngZoom(homeTarget, homeZoom));
  }

  Future<void> showLayers() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Warstwy mapy',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Alerty i komunikaty'),
                  subtitle: const Text(
                    'Alerty bezpieczeństwa i komunikaty widoczne na mapie',
                  ),
                  value: showEvents,
                  onChanged: (value) {
                    setState(() => showEvents = value);
                    update(() {});
                    unawaited(syncContextLayers());
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ostrzeżenia IMGW'),
                  subtitle: const Text(
                    'Ostrzeżenia meteorologiczne i hydrologiczne',
                  ),
                  value: showImgw,
                  onChanged: (value) {
                    setState(() => showImgw = value);
                    update(() {});
                    unawaited(syncContextLayers());
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Obserwowane miejsca'),
                  value: showWatched,
                  onChanged: (value) {
                    setState(() => showWatched = value);
                    update(() {});
                    unawaited(syncContextLayers());
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Pomiary promieniowania PAA'),
                  subtitle: const Text(
                    'Punkty pomiarowe Państwowej Agencji Atomistyki',
                  ),
                  value: showRadiation,
                  onChanged: (value) {
                    setState(() {
                      showRadiation = value;
                      if (!value) legendRadiationVisible = false;
                    });
                    update(() {});
                    if (value) {
                      unawaited(refreshRadiationSnapshot(force: true));
                    } else {
                      unawaited(refresh());
                    }
                  },
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey(availability),
                  initialValue: availability,
                  decoration: const InputDecoration(
                    labelText: 'Punkty schronienia',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'ALL', child: Text('Wszystkie')),
                    DropdownMenuItem(
                      value: '24H',
                      child: Text('Całodobowe wg źródła'),
                    ),
                    DropdownMenuItem(
                      value: 'ON_REQUEST',
                      child: Text('Na żądanie'),
                    ),
                    DropdownMenuItem(
                      value: 'LIMITED_HOURS',
                      child: Text('Określone godziny'),
                    ),
                    DropdownMenuItem(
                      value: 'UNKNOWN',
                      child: Text('Dostępność nieustalona'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => availability = value);
                    update(() {});
                    unawaited(refresh());
                  },
                ),
                const SizedBox(height: 12),
                const Text(
                  'Legenda na mapie aktualizuje się automatycznie i pokazuje tylko te typy danych, które są faktycznie widoczne w bieżącym kadrze.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fresh = online && viewport?.freshAt(DateTime.now()) == true;
    final showMapLegend =
        legendAlertsVisible ||
        legendImgwVisible ||
        legendSheltersVisible ||
        legendWatchedVisible ||
        legendRadiationVisible;
    Widget gpsLegend(Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: (MediaQuery.sizeOf(context).height * 0.62)
              .clamp(430.0, 620.0)
              .toDouble(),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                MapLibreMap(
                  styleString: onlineStyle,
                  gestureRecognizers: mapGestureRecognizers(),
                  initialCameraPosition: CameraPosition(
                    target: widget.ukraine ? const LatLng(49, 31) : homeTarget,
                    zoom: widget.ukraine ? 5 : homeZoom,
                  ),
                  trackCameraPosition: true,
                  minMaxZoomPreference: const MinMaxZoomPreference(0, 22),
                  onMapCreated: (c) {
                    if (!mounted) return;
                    controller = c;
                    c.onCircleTapped.add((circle) {
                      if (!mounted) return;
                      unawaited(openShelterCircle(circle));
                    });
                    armStyleFallback(c);
                  },
                  onStyleLoadedCallback: styled,
                  onCameraIdle: idle,
                  onMapClick: tapped,
                  featureTapsTriggersMapClick: true,
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Column(
                    children: [
                      IconButton.filledTonal(
                        tooltip: 'Przybliż',
                        onPressed: () => zoom(1),
                        icon: const Icon(Icons.add),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Oddal',
                        onPressed: () => zoom(-1),
                        icon: const Icon(Icons.remove),
                      ),
                    ],
                  ),
                ),
                if (!widget.ukraine)
                  Positioned(
                    right: 8,
                    top: 112,
                    child: IconButton.filledTonal(
                      tooltip: 'Pokaż moją lokalizację',
                      onPressed: locating ? null : locateUser,
                      icon: locating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location),
                    ),
                  ),
                if (!widget.ukraine)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Column(
                      children: [
                        IconButton.filledTonal(
                          tooltip: 'Warstwy mapy',
                          onPressed: showLayers,
                          icon: const Icon(Icons.layers_outlined),
                        ),
                        IconButton.filledTonal(
                          tooltip: 'Wróć do wybranej miejscowości',
                          onPressed: goHome,
                          icon: const Icon(Icons.home_outlined),
                        ),
                      ],
                    ),
                  ),
                if (!widget.ukraine)
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Material(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            child: Text(
                              overviewMode
                                  ? 'ZDARZENIA • POLSKA'
                                  : online && viewport != null
                                  ? fresh
                                        ? 'LIVE'
                                        : 'ONLINE / źródło STALE'
                                  : viewport != null
                                  ? 'OFFLINE / zapisane'
                                  : 'Ładowanie danych',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                        ),
                        if (showMapLegend) ...[
                          const SizedBox(height: 6),
                          _MapLegend(
                            showAlerts: legendAlertsVisible,
                            showImgw: legendImgwVisible,
                            showShelters: legendSheltersVisible,
                            showWatched: legendWatchedVisible,
                            showRadiation: legendRadiationVisible,
                          ),
                        ],
                      ],
                    ),
                  ),
                if (loading)
                  const Align(
                    alignment: Alignment.topCenter,
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
        ),
        if (!widget.ukraine) ...[
          const SizedBox(height: 10),
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: FilterChip(
                          avatar: const Icon(Icons.satellite_alt_outlined),
                          label: Text(
                            showGpsInterference
                                ? 'Zakłócenia GPS/GNSS — włączone'
                                : 'Zakłócenia GPS/GNSS',
                          ),
                          selected: showGpsInterference,
                          onSelected: (value) {
                            unawaited(setGpsInterferenceVisible(value));
                          },
                        ),
                      ),
                      if (gpsInterferenceLoading)
                        const Padding(
                          padding: EdgeInsets.only(left: 10),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                    ],
                  ),
                  if (showGpsInterference) ...[
                    const SizedBox(height: 8),
                    Text(
                      gpsInterference == null
                          ? 'Ładowanie dobowej mapy zakłóceń…'
                          : 'Dane dobowe: ${gpsInterference!.dataDate} UTC',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 14,
                      runSpacing: 6,
                      children: [
                        gpsLegend(const Color(0xff43a047), 'Niskie 0–2%'),
                        gpsLegend(const Color(0xfffdd835), 'Średnie >2–10%'),
                        gpsLegend(const Color(0xffe53935), 'Wysokie >10%'),
                      ],
                    ),
                    const SizedBox(height: 7),
                    const Text(
                      'Kolorowe heksy pokazują obszary, w których samoloty raportowały obniżoną dokładność nawigacji. Dane są agregowane dobowo i nie dowodzą celowego zagłuszania.',
                    ),
                    if (gpsInterferenceError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Warstwa chwilowo niedostępna: $gpsInterferenceError',
                        ),
                      ),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: gpsInterferenceLoading
                              ? null
                              : () => unawaited(
                                  refreshGpsInterferenceForCurrentViewport(),
                                ),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Odśwież'),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () =>
                              widget.openLink('https://gpsjam.org/faq'),
                          child: const Text('GPSJAM'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        if (!widget.ukraine && showRadiation) ...[
          Text(
            currentRadiation == null
                ? message
                : RadiationData.parse(
                    currentRadiation,
                  ).measurementText(DateTime.now(), currentRadiationOnline),
          ),
          const Text(
            'Komunikaty PAA są dostępne w Statusie i Alert Center. Brak punktów na mapie nie oznacza braku zagrożenia.',
          ),
          TextButton(
            onPressed: () =>
                widget.openLink('https://monitoring.paa.gov.pl/maps-portal/'),
            child: const Text('Oficjalna mapa PAA'),
          ),
        ],
        if (!widget.ukraine) ...[
          if (fallbackStyle)
            FilledButton.tonalIcon(
              onPressed: retryOnlineStyle,
              icon: const Icon(Icons.map_outlined),
              label: const Text('Ponów podkład mapy'),
            ),
          if (message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(message),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    if (showRadiation) {
                      unawaited(refreshRadiationSnapshot(force: true));
                    } else {
                      unawaited(refresh());
                    }
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Odśwież'),
                ),
                const Spacer(),
                Text(
                  overviewMode
                      ? 'Aktywne zdarzenia'
                      : viewport == null
                      ? ''
                      : online
                      ? fresh
                            ? 'Dane bieżące'
                            : 'Połączono • źródło STALE'
                      : 'Ostatnia zapisana kopia',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
        TextButton(
          onPressed: () => widget.openLink('https://openfreemap.org/'),
          child: const Text(
            'Mapa: OpenFreeMap • OpenMapTiles • © OpenStreetMap',
          ),
        ),
      ],
    );
  }
}
