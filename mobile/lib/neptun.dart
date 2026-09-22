import 'dart:async';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'model.dart';

class NeptunData {
  final Map<String, dynamic> data;
  NeptunData._(this.data);

  factory NeptunData.parse(dynamic input) {
    if (input is! Map) throw const FormatException('Niepoprawne dane NEPTUN');
    final m = Map<String, dynamic>.from(input);
    final delay = m['safetyDelayHours'], minimum = m['minimumPublishedPrecisionKm'];
    if (m['schemaVersion'] != 1 ||
        m['mode'] != 'HISTORICAL_ONLY' ||
        delay is! num ||
        delay < 24 ||
        minimum is! num ||
        minimum < 10 ||
        m['tracks'] is! List ||
        (m['tracks'] as List).length > 500 ||
        m['map'] is! Map ||
        m['map']['type'] != 'FeatureCollection' ||
        m['map']['features'] is! List ||
        !['NO_CONFIGURED_FEED', 'CURATED_HISTORY'].contains(m['coverage'])) {
      throw const FormatException('Nieobsługiwany kontrakt NEPTUN');
    }
    final server = DateTime.parse(m['serverTime'] as String);
    final cutoff = server.subtract(Duration(hours: delay.toInt()));
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
          !['CONFIRMED', 'PROBABLE', 'UNVERIFIED', 'REFUTED', 'DISPUTED'].contains(t['verification']) ||
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
        final lat = o['latitude'], lon = o['longitude'], precision = o['precisionKm'];
        final hasCoordinates = lat != null || lon != null;
        if ((lat == null) != (lon == null) ||
            (hasCoordinates && precision == null) ||
            (!hasCoordinates && precision != null) ||
            (lat != null && (lat is! num || !lat.isFinite || lat.abs() > 90)) ||
            (lon != null && (lon is! num || !lon.isFinite || lon.abs() > 180)) ||
            (precision != null && (precision is! num || !precision.isFinite || precision < minimum))) {
          throw const FormatException('Zbyt dokładna lub błędna geometria NEPTUN');
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

  List<Map<String, dynamic>> get tracks => (data['tracks'] as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
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
  bool loading = false, online = false;
  String? error;

  @override
  void initState() {
    super.initState();
    snapshot = widget.repository.cachedNeptun();
    if (widget.repository.api.isNotEmpty) unawaited(refresh());
  }

  Future<void> refresh() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.repository.refreshNeptun();
      if (!mounted) return;
      setState(() {
        snapshot = result;
        online = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        online = false;
        error = apiFailureMessage(e);
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String when(dynamic value) => value is String ? stamp(value) : 'Nie podano';

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
            if ((t['description'] as String).isNotEmpty) Text(t['description'] as String),
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
                      onPressed: () => widget.openSource(o['source']['url'] as String),
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
    final tracks = snapshot?.tracks ?? const <Map<String, dynamic>>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('NEPTUN • historia'),
        actions: [
          IconButton(
            onPressed: loading || widget.repository.api.isEmpty ? null : refresh,
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
            const Text(
              'Historyczny przebieg zdarzeń OSINT. NEPTUN nie pokazuje aktywnych dokładnych pozycji ani nie wpływa na status Polski.',
            ),
            const SizedBox(height: 8),
            Text(
              'Tryb: ${snapshot?.data['mode'] ?? 'HISTORICAL_ONLY'} • opóźnienie publikacji: ${snapshot?.data['safetyDelayHours'] ?? 24} h • minimalna dokładność: ${snapshot?.data['minimumPublishedPrecisionKm'] ?? 10} km',
            ),
            Text(
              'Pokrycie: ${snapshot?.data['coverage'] ?? 'NO_CONFIGURED_FEED'}${online ? '' : ' • offline / ostatnia poprawna kopia'}',
            ),
            if (loading) const LinearProgressIndicator(),
            if (error != null) Text(error!),
            const SizedBox(height: 12),
            if (widget.showMap && snapshot != null && tracks.isNotEmpty)
              NeptunMap(data: snapshot!),
            const SizedBox(height: 8),
            const Text(
              'Brak śladów nie oznacza braku zdarzeń. Dane są publikowane dopiero po zakończeniu i dodatkowym opóźnieniu bezpieczeństwa; współrzędne są zgrubne.',
            ),
            const SizedBox(height: 12),
            if (tracks.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'Brak opublikowanych historycznych śladów NEPTUN. Źródło live nie jest skonfigurowane.',
                  ),
                ),
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

  Future<void> styled() async {
    try {
      await controller?.addSource(
        'neptun-tracks',
        GeojsonSourceProperties(data: widget.data.data['map']),
      );
      await controller?.addLineLayer(
        'neptun-tracks',
        'neptun-track-lines',
        const LineLayerProperties(
          lineColor: '#7062c8',
          lineWidth: 4,
          lineOpacity: 0.72,
        ),
      );
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
    children: [
      SizedBox(
        height: 320,
        child: MapLibreMap(
          styleString: const String.fromEnvironment(
            'MAP_STYLE_URL',
            defaultValue: 'https://tiles.openfreemap.org/styles/liberty',
          ),
          initialCameraPosition: const CameraPosition(
            target: LatLng(50.3, 25.0),
            zoom: 4.2,
          ),
          onMapCreated: (c) => controller = c,
          onStyleLoadedCallback: styled,
        ),
      ),
      const Text(
        'Linie pokazują wyłącznie zgrubny, historyczny przebieg po zakończeniu zdarzenia.',
      ),
      if (error != null) Text(error!),
    ],
  );
}
