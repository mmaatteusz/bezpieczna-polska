import 'radiation.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'map_layers.dart';
import 'model.dart';
import 'shelters.dart';

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
  Timer? debounce, clock, styleFallback;
  bool showRadiation = false, locating = false;
  bool showEvents = true, showWatched = true;
  bool ready = false, loading = false, online = false, fallbackStyle = false;
  int ticket = 0;
  String availability = 'ALL', message = 'Przygotowywanie mapy…';
  MapViewport? viewport;
  ShelterMapProvider get provider => ShelterMapProvider(widget.repository);
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
    clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant ShelterMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (showRadiation &&
        (oldWidget.radiation != widget.radiation ||
            oldWidget.radiationOnline != widget.radiationOnline)) {
      idle();
    }
    if (oldWidget.events != widget.events ||
        oldWidget.watchedLocations != widget.watchedLocations) {
      unawaited(syncContextLayers());
    }
  }

  @override
  void dispose() {
    ticket++;
    debounce?.cancel();
    clock?.cancel();
    styleFallback?.cancel();
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
    final c = controller;
    if (c == null) return;
    styleFallback?.cancel();
    try {
      await c.addSource('radiation', GeojsonSourceProperties(data: empty));
      await c.addCircleLayer(
        'radiation',
        'radiation-points',
        const CircleLayerProperties(circleColor: '#7563b8', circleRadius: 7),
      );
      await c.addSource('shelters', GeojsonSourceProperties(data: empty));
      await c.addCircleLayer(
        'shelters',
        'shelter-points',
        const CircleLayerProperties(
          circleColor: '#25877b',
          circleRadius: 6,
          circleStrokeColor: '#ffffff',
          circleStrokeWidth: 1,
        ),
        filter: [
          '==',
          ['get', 'cluster'],
          false,
        ],
      );
      await c.addCircleLayer(
        'shelters',
        'shelter-clusters',
        const CircleLayerProperties(
          circleColor: '#205f73',
          circleRadius: 19,
          circleStrokeColor: '#ffffff',
          circleStrokeWidth: 1,
        ),
        filter: [
          '==',
          ['get', 'cluster'],
          true,
        ],
      );
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
        'event-points',
        const CircleLayerProperties(
          circleColor: '#b3261e',
          circleRadius: 8,
          circleStrokeColor: '#ffffff',
          circleStrokeWidth: 2,
        ),
      );
      await c.addSource('watched', GeojsonSourceProperties(data: empty));
      await c.addCircleLayer(
        'watched',
        'watched-points',
        const CircleLayerProperties(
          circleColor: '#315da8',
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
          circleColor: '#1565c0',
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

  Future<void> syncContextLayers() async {
    final c = controller;
    if (!ready || c == null || widget.ukraine) return;

    final eventFeatures = showEvents && !showRadiation
        ? widget.events
              .where((event) => event.hasPoint)
              .map(
                (event) => {
                  'type': 'Feature',
                  'geometry': {
                    'type': 'Point',
                    'coordinates': [
                      (event.data['longitude'] as num).toDouble(),
                      (event.data['latitude'] as num).toDouble(),
                    ],
                  },
                  'properties': {'eventId': event.id, 'title': event.title},
                },
              )
              .toList()
        : <Map<String, dynamic>>[];
    final watchedFeatures = showWatched && !showRadiation
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
  }

  Future<void> refresh() async {
    final c = controller;
    if (!ready || c == null || widget.ukraine) return;
    final current = ++ticket;
    setState(() {
      loading = true;
      online = false;
    });
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
      if (showRadiation) {
        await syncContextLayers();
        final data = widget.radiation == null
            ? null
            : RadiationData.parse(widget.radiation);
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
        await c.setGeoJsonSource('shelters', empty);
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
        if (!mounted || current != ticket) return;
        setState(() {
          viewport = null;
          message =
              data?.measurementText(DateTime.now(), widget.radiationOnline) ??
              'PAA: brak danych pomiarowych';
        });
        return;
      }
      await c.setGeoJsonSource('radiation', empty);
      await syncContextLayers();
      request = MapRequest(
        [west, south, east, north],
        (c.cameraPosition?.zoom ?? 5).clamp(0, 22).toDouble(),
        widget.region,
        availability,
      );
      // Remove old viewport immediately: it must not masquerade as this area/filter.
      viewport = null;
      await c.setGeoJsonSource('shelters', empty);
      final result = await provider.fetch(request);
      if (!mounted || current != ticket) return;
      await c.setGeoJsonSource('shelters', result.data);
      if (!mounted || current != ticket) return;
      setState(() {
        viewport = result;
        online = true;
        message = '';
      });
    } catch (failure) {
      if (!mounted || current != ticket) return;
      final cached = request == null ? null : provider.cached(request);
      final offline = cached == null && request != null
          ? await provider.offline(request)
          : null;
      final fallback = cached ?? offline;
      if (fallback != null) {
        await c.setGeoJsonSource('shelters', fallback.data);
      }
      if (!mounted || current != ticket) return;
      setState(() {
        viewport = fallback;
        online = false;
        message = fallback == null
            ? apiFailureMessage(failure)
            : offline != null
            ? 'OFFLINE • lokalny overlay schronień z pakietu z ${stamp(offline.metadata['offlinePackageTimestamp'])}. Podkład bazowy OpenFreeMap nie jest częścią pakietu i może być niedostępny. Brak nowych danych nie oznacza bezpieczeństwa.'
            : 'Pokazano zapisaną kopię viewportu. ${apiFailureMessage(failure)}';
      });
    } finally {
      if (mounted && current == ticket) setState(() => loading = false);
    }
  }

  Future<void> tapped(math.Point<double> point, LatLng location) async {
    final c = controller;
    if (c == null || !ready) return;
    try {
      if (showRadiation) {
        final points = await c.queryRenderedFeatures(point, [
          'radiation-points',
        ], null);
        if (points.isEmpty || !mounted) return;
        final p = (points.first as Map)['properties'] as Map;
        final data = widget.radiation == null
            ? null
            : RadiationData.parse(widget.radiation);
        await showModalBottomSheet<void>(
          context: context,
          builder: (_) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                '${p['name']}\n${p['value']} ${p['unit']}\nPomiar: ${stamp(p['measuredAt'])}\n${data?.measurementText(DateTime.now(), widget.radiationOnline) ?? 'STALE'}\nPomiar nie jest alarmem.',
              ),
            ),
          ),
        );
        return;
      }
      final contextHits = await c.queryRenderedFeatures(point, [
        'event-points',
        'watched-points',
      ], null);
      if (contextHits.isNotEmpty && mounted) {
        final properties = Map<String, dynamic>.from(
          (contextHits.first as Map)['properties'] as Map,
        );
        final eventId = properties['eventId']?.toString();
        if (eventId != null) {
          for (final event in widget.events) {
            if (event.id == eventId) {
              widget.openEvent(event);
              return;
            }
          }
        }
        final locationId = properties['locationId']?.toString();
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
      final hits = await c.queryRenderedFeatures(point, [
        'shelter-points',
        'shelter-clusters',
      ], null);
      if (hits.isEmpty || !mounted) return;
      final f = hits.first as Map,
          p = Map<String, dynamic>.from(f['properties'] as Map);
      if (p['cluster'] == true) {
        final coordinates = f['geometry']['coordinates'] as List;
        await c.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(
              (coordinates[1] as num).toDouble(),
              (coordinates[0] as num).toDouble(),
            ),
            (p['expansionZoom'] as num).toDouble(),
          ),
        );
        return;
      }
      final shelter = ShelterPoint.parse(p);
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
                Text('${p['municipality']} • ${p['county']}'),
                Text(shelter.availability),
                const Text(
                  'Punkt schronienia wg PSP. Klasa ochrony, pojemność i bieżący dostęp nie są potwierdzone.',
                ),
                Text('Data danych: ${p['dataDate']}'),
                if (!online || viewport?.freshAt(DateTime.now()) != true)
                  const Text(
                    'Ostatnie zapisane dane — aktualność niepotwierdzona',
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
                  title: const Text('Zdarzenia'),
                  value: showEvents && !showRadiation,
                  onChanged: showRadiation
                      ? null
                      : (value) {
                          setState(() => showEvents = value);
                          update(() {});
                          unawaited(syncContextLayers());
                        },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Obserwowane miejsca'),
                  value: showWatched && !showRadiation,
                  onChanged: showRadiation
                      ? null
                      : (value) {
                          setState(() => showWatched = value);
                          update(() {});
                          unawaited(syncContextLayers());
                        },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Radiacja / PAA'),
                  subtitle: const Text('Pomiary jako osobna warstwa'),
                  value: showRadiation,
                  onChanged: (value) {
                    setState(() => showRadiation = value);
                    update(() {});
                    unawaited(refresh());
                  },
                ),
                if (!showRadiation)
                  DropdownButtonFormField<String>(
                    initialValue: availability,
                    decoration: const InputDecoration(
                      labelText: 'Punkty schronienia',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'ALL',
                        child: Text('Wszystkie'),
                      ),
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
                  'Czerwone: zdarzenia • zielone: schronienia • niebieskie: obserwowane miejsca • fioletowe: PAA',
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
                  initialCameraPosition: CameraPosition(
                    target: widget.ukraine ? const LatLng(49, 31) : homeTarget,
                    zoom: widget.ukraine ? 5 : homeZoom,
                  ),
                  trackCameraPosition: true,
                  minMaxZoomPreference: const MinMaxZoomPreference(0, 22),
                  onMapCreated: (c) {
                    controller = c;
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
                    bottom: 8,
                    child: Material(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: Text(
                          showRadiation
                              ? 'PAA'
                              : fresh
                              ? 'LIVE'
                              : viewport != null
                              ? 'OFFLINE / zapisane'
                              : 'Ładowanie danych',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
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
        if (!widget.ukraine && showRadiation) ...[
          Text(
            widget.radiation == null
                ? message
                : RadiationData.parse(
                    widget.radiation,
                  ).measurementText(DateTime.now(), widget.radiationOnline),
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
        if (!widget.ukraine && !showRadiation) ...[
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
                  onPressed: refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Odśwież'),
                ),
                const Spacer(),
                Text(
                  viewport == null
                      ? ''
                      : fresh
                      ? 'Dane bieżące'
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
