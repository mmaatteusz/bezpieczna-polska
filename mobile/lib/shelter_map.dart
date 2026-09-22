import 'radiation.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
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
  final void Function(String) openLink;
  const ShelterMap({
    super.key,
    this.radiation,
    this.radiationOnline = false,
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
  Timer? debounce, clock;
  bool showRadiation = false;
  bool ready = false, loading = false, online = false;
  int ticket = 0;
  String availability = 'ALL', message = 'Przygotowywanie mapy…';
  MapViewport? viewport;
  ShelterMapProvider get provider => ShelterMapProvider(widget.repository);
  static const empty = {'type': 'FeatureCollection', 'features': <dynamic>[]};
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
  }

  @override
  void dispose() {
    ticket++;
    debounce?.cancel();
    clock?.cancel();
    super.dispose();
  }

  Future<void> styled() async {
    final c = controller;
    if (c == null) return;
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
      if (!mounted) return;
      ready = true;
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

  void zoom(double delta) {
    final c = controller, position = controller?.cameraPosition;
    if (c != null && position != null) {
      c.animateCamera(
        CameraUpdate.zoomTo((position.zoom + delta).clamp(0, 22).toDouble()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fresh = online && viewport?.freshAt(DateTime.now()) == true,
        meta = viewport?.metadata;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.ukraine)
          SwitchListTile(
            title: const Text('Radiacja / PAA'),
            subtitle: const Text('Pomiary oddzielone od komunikatów'),
            value: showRadiation,
            onChanged: (value) {
              setState(() => showRadiation = value);
              refresh();
            },
          ),
        if (!widget.ukraine && !showRadiation)
          DropdownButton<String>(
            isExpanded: true,
            value: availability,
            items: const [
              DropdownMenuItem(
                value: 'ALL',
                child: Text('Punkty schronienia • wszystkie'),
              ),
              DropdownMenuItem(
                value: '24H',
                child: Text('Całodobowe wg źródła'),
              ),
              DropdownMenuItem(value: 'ON_REQUEST', child: Text('Na żądanie')),
              DropdownMenuItem(
                value: 'LIMITED_HOURS',
                child: Text('Określone godziny'),
              ),
              DropdownMenuItem(
                value: 'UNKNOWN',
                child: Text('Dostępność nieustalona'),
              ),
            ],
            onChanged: (v) {
              if (v != null) {
                setState(() => availability = v);
                refresh();
              }
            },
          ),
        SizedBox(
          height: 350,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                MapLibreMap(
                  styleString: const String.fromEnvironment(
                    'MAP_STYLE_URL',
                    defaultValue:
                        'https://tiles.openfreemap.org/styles/liberty',
                  ),
                  initialCameraPosition: CameraPosition(
                    target: widget.ukraine
                        ? const LatLng(49, 31)
                        : const LatLng(52.1, 19.4),
                    zoom: 5,
                  ),
                  trackCameraPosition: true,
                  minMaxZoomPreference: const MinMaxZoomPreference(0, 22),
                  onMapCreated: (c) => controller = c,
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
          if (viewport != null)
            Text(
              '${fresh ? 'LIVE • dane pobrane z PSP' : meta?['offlinePackageTimestamp'] != null ? 'OFFLINE • LAST KNOWN GOOD • snapshot ${stamp(meta?['offlinePackageTimestamp'])}' : 'Ostatnie zapisane dane — aktualność niepotwierdzona'}\nData danych: ${meta?['dataDate'] ?? 'Nie podano'} • Aktualność źródła: ${stamp(meta?['health']?['lastSuccess'])}\nPunkty w widocznym obszarze: ${meta?['total']}',
            ),
          if (message.isNotEmpty) Text(message),
          Wrap(
            children: [
              TextButton.icon(
                onPressed: refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Odśwież obszar'),
              ),
              TextButton(
                onPressed: () => widget.openLink(
                  'https://dane.gov.pl/pl/dataset/28058,punkty-schronienia-w-polsce',
                ),
                child: const Text('Źródło: KG PSP / dane.gov.pl'),
              ),
            ],
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