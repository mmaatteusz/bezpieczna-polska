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
  final void Function(String) openLink;
  const ShelterMap({
    super.key,
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
      if (cached != null) await c.setGeoJsonSource('shelters', cached.data);
      if (!mounted || current != ticket) return;
      setState(() {
        viewport = cached;
        online = false;
        message = cached == null
            ? apiFailureMessage(failure)
            : 'Pokazano zapisaną kopię. ${apiFailureMessage(failure)}';
      });
    } finally {
      if (mounted && current == ticket) setState(() => loading = false);
    }
  }

  Future<void> tapped(math.Point<double> point, LatLng location) async {
    final c = controller;
    if (c == null || !ready) return;
    try {
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
        if (!widget.ukraine) ...[
          if (viewport != null)
            Text(
              '${fresh ? 'Dane pobrane z PSP' : 'Ostatnie zapisane dane — aktualność niepotwierdzona'}\nData danych: ${meta?['dataDate'] ?? 'Nie podano'} • Aktualność: ${stamp(meta?['health']?['lastSuccess'])}\nPunkty w widocznym obszarze: ${meta?['total']}',
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
