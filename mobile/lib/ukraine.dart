import 'dart:async';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'model.dart';

class UkraineData {
  final Map<String, dynamic> data;
  UkraineData._(this.data);
  factory UkraineData.parse(dynamic raw) {
    if (raw is! Map) throw const FormatException('Niepoprawne dane UA');
    final m = Map<String, dynamic>.from(raw);
    if (m['schemaVersion'] != 1 ||
        m['countryCode'] != 'UA' ||
        !['partial', 'stale', 'unavailable'].contains(m['coverage']) ||
        m['events'] is! List ||
        (m['events'] as List).length > 1100 ||
        m['revisions'] is! List ||
        (m['revisions'] as List).length > 5500 ||
        m['regions'] is! List ||
        (m['regions'] as List).length > 5000 ||
        m['map'] is! Map ||
        m['map']['type'] != 'FeatureCollection' ||
        m['map']['features'] is! List) {
      throw const FormatException('Nieobsługiwany kontrakt UA');
    }
    DateTime.parse(m['serverTime'] as String);
    for (final key in ['lastSuccessfulSyncAt', 'validUntil']) {
      if (m[key] != null) DateTime.parse(m[key] as String);
    }
    final h = m['sourceHealth'];
    if (h != null &&
        (h is! Map ||
            h['id'] != 'UA' ||
            ![
              'HEALTHY',
              'STALE',
              'BROKEN',
              'DEGRADED',
              'NOT_CONFIGURED',
            ].contains(h['state']) ||
            h['maxAgeSeconds'] is! num)) {
      throw const FormatException('Niepoprawny stan źródła UA');
    }
    final ids = <String>{};
    void validateEvent(dynamic raw) {
      final e = SafetyEvent.parse(raw), u = e.data['ukraine'];
      if (e.data['countryCode'] != 'UA' ||
          e.data['origin'] != 'OFFICIAL_FOREIGN' ||
          e.areas.isNotEmpty ||
          !e.sources.any((s) => s['id'] == 'UA') ||
          u is! Map ||
          u['regionId'] is! String ||
          u['regionName'] is! String ||
          !['State', 'District', 'Community'].contains(u['regionType']) ||
          !['OFFICIAL_ALERT', 'OFFICIAL_INFORMATION'].contains(u['kind']) ||
          !['ACTIVE', 'ENDED', 'UNKNOWN'].contains(e.data['lifecycle'])) {
        throw const FormatException('Niespójny alarm UA');
      }
      for (final key in [
        'validFrom',
        'validTo',
        'retrievedAt',
        'publishedAt',
      ]) {
        if (e.data[key] != null) DateTime.parse(e.data[key] as String);
      }
      if (e.data['lifecycle'] == 'ENDED' && e.data['validTo'] == null) {
        throw const FormatException('Brak źródłowego końca alarmu');
      }
    }

    for (final e in m['events'] as List) {
      validateEvent(e);
      if (!ids.add(e['id'] as String) ||
          !['FRESH', 'STALE'].contains(e['freshness'])) {
        throw const FormatException('Powielony lub nieaktualny kontrakt UA');
      }
    }
    for (final r in m['revisions'] as List) {
      if (r is! Map ||
          r['payload'] is! Map ||
          !ids.contains(r['payload']['id']) ||
          r['changes'] is! List) {
        throw const FormatException('Niepoprawna historia UA');
      }
      DateTime.parse(r['recorded_at'] as String);
      validateEvent(r['payload']);
    }
    for (final f in m['map']['features'] as List) {
      if (f is! Map ||
          f['geometry'] is! Map ||
          !['Polygon', 'MultiPolygon'].contains(f['geometry']['type']) ||
          f['properties'] is! Map ||
          !ids.contains(f['properties']['eventId'])) {
        throw const FormatException('Niepoprawna warstwa UA');
      }
      void coordinates(dynamic v) {
        if (v is! List || v.isEmpty)
          throw const FormatException('Geometria UA');
        if (v.first is num) {
          if (v.length != 2 ||
              v[0] is! num ||
              v[1] is! num ||
              !(v[0] as num).isFinite ||
              !(v[1] as num).isFinite ||
              (v[0] as num).abs() > 180 ||
              (v[1] as num).abs() > 90) {
            throw const FormatException('Współrzędne UA');
          }
        } else {
          for (final child in v) {
            coordinates(child);
          }
        }
      }

      coordinates(f['geometry']['coordinates']);
    }
    return UkraineData._(m);
  }
  bool freshAt(DateTime now, bool online) {
    final h = data['sourceHealth'];
    if (!online || h is! Map || h['state'] != 'HEALTHY') return false;
    final last = DateTime.tryParse(
      data['lastSuccessfulSyncAt'] as String? ?? '',
    );
    final until = DateTime.tryParse(data['validUntil'] as String? ?? '');
    return last != null &&
        until != null &&
        !last.isAfter(now.add(const Duration(seconds: 30))) &&
        now.isBefore(until);
  }

  Map<String, dynamic> mapAt(DateTime now, bool online) => {
    'type': 'FeatureCollection',
    'features': [
      for (final f in data['map']['features'] as List)
        {
          ...Map<String, dynamic>.from(f as Map),
          'properties': {
            ...Map<String, dynamic>.from(f['properties'] as Map),
            'freshness': freshAt(now, online)
                ? f['properties']['freshness']
                : 'STALE',
          },
        },
    ],
  };
}

class UkrainePanel extends StatefulWidget {
  final DataRepository repository;
  final void Function(String) openSource;
  final bool showMap;
  const UkrainePanel({
    super.key,
    required this.repository,
    required this.openSource,
    this.showMap = true,
  });
  @override
  State<UkrainePanel> createState() => _UkrainePanelState();
}

class _UkrainePanelState extends State<UkrainePanel>
    with WidgetsBindingObserver {
  UkraineData? snapshot;
  bool online = false, loading = false;
  String? error;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    snapshot = widget.repository.cachedUkraine();
    unawaited(refresh());
    timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() {});
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed)
        unawaited(refresh());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> refresh() async {
    if (loading) return;
    setState(() {
      loading = true;
    });
    try {
      final result = await widget.repository.refreshUkraine();
      if (mounted)
        setState(() {
          snapshot = result;
          online = true;
          error = null;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          online = false;
          error = apiFailureMessage(e);
        });
    } finally {
      if (mounted)
        setState(() {
          loading = false;
        });
    }
  }

  String time(dynamic v) => v == null
      ? 'Nie podano'
      : DateTime.parse(v as String).toLocal().toString();
  @override
  Widget build(BuildContext context) {
    final fresh = snapshot?.freshAt(DateTime.now(), online) == true;
    final data = snapshot?.data;
    final events = (data?['events'] as List? ?? []).cast<Map>();
    final alerts = events
        .where(
          (e) =>
              e['ukraine']['kind'] == 'OFFICIAL_ALERT' &&
              ['ACTIVE', 'UNKNOWN'].contains(e['lifecycle']),
        )
        .toList();
    final history = events.where((e) => e['lifecycle'] == 'ENDED').toList();
    Widget card(Map e) => Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              e['title'] as String,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              '${e['ukraine']['regionName']} • ${e['ukraine']['regionType']}',
            ),
            Text(
              '${e['ukraine']['kind']} • ${e['lifecycle']} • ${fresh && e['freshness'] == 'FRESH' ? 'FRESH' : 'STALE'}',
            ),
            Text('Rozpoczęcie: ${time(e['validFrom'])}'),
            Text('Zakończenie: ${time(e['validTo'])}'),
            Text(
              'Aktualizacja źródła: ${time(e['ukraine']['sourceUpdatedAt'])}',
            ),
            if (e['geometry'] == null)
              const Text(
                'Brak zweryfikowanej geometrii — alarm dostępny na liście.',
              ),
            ExpansionTile(
              title: Text('Historia alarmu • rewizja ${e['revision']}'),
              children: [
                for (final r in data?['revisions'] as List? ?? [])
                  if (r['payload']['id'] == e['id'])
                    ListTile(
                      dense: true,
                      title: Text(
                        'Rewizja ${r['payload']['revision']} • ${r['payload']['lifecycle']}',
                      ),
                      subtitle: Text(
                        'Zapis: ${time(r['recorded_at'])}\nPoczątek: ${time(r['payload']['validFrom'])}\nKoniec: ${time(r['payload']['validTo'])}\n${r['reason']}',
                      ),
                    ),
              ],
            ),
            TextButton(
              onPressed: () =>
                  widget.openSource('https://map.ukrainealarm.com/'),
              child: const Text('Źródło: UkraineAlarm'),
            ),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Ukraina',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            IconButton(
              onPressed: loading ? null : refresh,
              icon: const Icon(Icons.refresh),
              tooltip: 'Odśwież alarmy Ukrainy',
            ),
          ],
        ),
        const Text(
          'Oficjalne alarmy obrony cywilnej. Status Polski jest oceniany niezależnie.',
        ),
        Text(
          'Źródło: ${data?['healthStatus'] ?? 'NOT_CONFIGURED'} • ${fresh ? 'ostatnia synchronizacja aktualna' : 'STALE / brak bieżącego pokrycia'}',
        ),
        Text('Ostatnia synchronizacja: ${time(data?['lastSuccessfulSyncAt'])}'),
        Text(
          'Pokrycie: ${fresh ? (data?['coverage']) : 'brak potwierdzonej aktualności'}',
        ),
        if (data?['sourceHealth']?['errorCode'] != null)
          Text(data!['sourceHealth']['errorCode'] as String),
        if (loading) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        const SizedBox(height: 12),
        if (widget.showMap) UkraineMap(data: snapshot, online: online),
        const Text(
          'Brak oznaczeń lub wpisów nie oznacza braku alarmu. Historia źródła i kopia offline są ograniczone. Podkład mapy wymaga internetu lub wcześniejszego cache.',
        ),
        const SizedBox(height: 12),
        Text(
          'Aktywne i nierozstrzygnięte alarmy (${alerts.length})',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (alerts.isEmpty)
          const Text('Brak potwierdzonego bieżącego stanu alarmów.'),
        ...alerts.map(card),
        ExpansionTile(
          title: const Text('Historia zakończonych alarmów'),
          children: history.map(card).toList(),
        ),
        ExpansionTile(
          title: const Text('Oficjalne informacje • oddzielnie od alarmów'),
          children: events
              .where((e) => e['ukraine']['kind'] == 'OFFICIAL_INFORMATION')
              .map(card)
              .toList(),
        ),
        TextButton(
          onPressed: () => widget.openSource('https://map.ukrainealarm.com/'),
          child: const Text('Otwórz oficjalną mapę Ukrainy'),
        ),
      ],
    );
  }
}

class UkraineMap extends StatefulWidget {
  final UkraineData? data;
  final bool online;
  const UkraineMap({super.key, required this.data, required this.online});
  @override
  State<UkraineMap> createState() => _UkraineMapState();
}

class _UkraineMapState extends State<UkraineMap> {
  MapLibreMapController? controller;
  bool ready = false;
  String? error;
  Future<void> update() async {
    if (!ready) return;
    try {
      await controller?.setGeoJsonSource(
        'ua-alerts',
        widget.data?.mapAt(DateTime.now(), widget.online) ??
            {'type': 'FeatureCollection', 'features': <dynamic>[]},
      );
    } catch (_) {
      if (mounted)
        setState(() {
          error = 'Warstwa mapy niedostępna; sprawdź listę alarmów.';
        });
    }
  }

  Future<void> styled() async {
    try {
      await controller?.addSource(
        'ua-alerts',
        GeojsonSourceProperties(
          data:
              widget.data?.mapAt(DateTime.now(), widget.online) ??
              {'type': 'FeatureCollection', 'features': <dynamic>[]},
        ),
      );
      await controller?.addFillLayer(
        'ua-alerts',
        'ua-alert-areas',
        const FillLayerProperties(
          fillColor: [
            'case',
            [
              '==',
              ['get', 'freshness'],
              'STALE',
            ],
            '#8b6b25',
            '#b94343',
          ],
          fillOpacity: 0.38,
          fillOutlineColor: '#913d36',
        ),
      );
      ready = true;
      await update();
    } catch (_) {
      if (mounted)
        setState(() {
          error = 'Warstwa mapy niedostępna; sprawdź listę alarmów.';
        });
    }
  }

  @override
  void didUpdateWidget(covariant UkraineMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    unawaited(update());
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
            target: LatLng(49, 31),
            zoom: 4.5,
          ),
          onMapCreated: (c) => controller = c,
          onStyleLoadedCallback: styled,
        ),
      ),
      const Text(
        'Czerwony: alarm wg aktualnego odczytu • ochra: STALE. Granice administracyjne: UN OCHA. Bez pozycji wojskowych.',
      ),
      if (error != null) Text(error!),
    ],
  );
}
