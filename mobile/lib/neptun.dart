import 'dart:async';
import 'dart:math' show Point;
import 'dart:typed_data';
import 'dart:ui' as ui;

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
          ![
            'uav',
            'fpv',
            'recon',
            'missile',
            'ballistic',
            'kab',
            'mig31k',
            'unknown',
          ].contains(rawFeature['properties']['type']) ||
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
      final matchingThreat = (live['threats'] as List).cast<Map>().firstWhere(
        (threat) => threat['id'] == rawFeature['properties']['threatId'],
      );
      if (matchingThreat['type'] != rawFeature['properties']['type']) {
        throw const FormatException('Niezgodny typ ikony NEPTUN');
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

String neptunMapIconId(String value) => switch (value) {
  'uav' => 'neptun-icon-uav',
  'fpv' => 'neptun-icon-fpv',
  'recon' => 'neptun-icon-recon',
  'missile' => 'neptun-icon-missile',
  'ballistic' => 'neptun-icon-ballistic',
  'kab' => 'neptun-icon-kab',
  'mig31k' => 'neptun-icon-mig31k',
  _ => 'neptun-icon-unknown',
};

const _neptunIconTypes = <String>[
  'uav',
  'fpv',
  'recon',
  'missile',
  'ballistic',
  'kab',
  'mig31k',
  'unknown',
];

ui.Color _neptunAccentColor(String type) => switch (type) {
  'uav' => const ui.Color(0xffffa726),
  'fpv' => const ui.Color(0xffffb74d),
  'recon' => const ui.Color(0xff42a5f5),
  'missile' => const ui.Color(0xffef5350),
  'ballistic' => const ui.Color(0xffd81b60),
  'kab' => const ui.Color(0xffc96a3d),
  'mig31k' => const ui.Color(0xffab47bc),
  _ => const ui.Color(0xff90a4ae),
};

Future<Uint8List> neptunIconPng(String type, {double pixelRatio = 1}) async {
  // Compact type badges are intentionally fixed upright. The marker shape and
  // colour describe the threat class only and must never imply heading/course.
  const logicalSize = 72.0;
  final outputSize = 40 * pixelRatio;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..scale(outputSize / logicalSize);
  final accent = _neptunAccentColor(type);

  final plate = ui.Paint()
    ..color = const ui.Color(0xe61a1f24)
    ..style = ui.PaintingStyle.fill;
  final ring = ui.Paint()
    ..color = accent
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 4;
  final white = ui.Paint()
    ..color = const ui.Color(0xffffffff)
    ..style = ui.PaintingStyle.fill;
  final whiteStroke = ui.Paint()
    ..color = const ui.Color(0xffffffff)
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 4
    ..strokeJoin = ui.StrokeJoin.round
    ..strokeCap = ui.StrokeCap.round;

  canvas.drawCircle(const ui.Offset(36, 36), 30, plate);
  canvas.drawCircle(const ui.Offset(36, 36), 29, ring);

  void fillPath(ui.Path path) => canvas.drawPath(path, white);
  void strokePath(ui.Path path, {double width = 4}) {
    final p = ui.Paint()
      ..color = const ui.Color(0xffffffff)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeJoin = ui.StrokeJoin.round
      ..strokeCap = ui.StrokeCap.round;
    canvas.drawPath(path, p);
  }

  void line(ui.Offset a, ui.Offset b, {double width = 4}) {
    final p = ui.Paint()
      ..color = const ui.Color(0xffffffff)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = ui.StrokeCap.round;
    canvas.drawLine(a, b, p);
  }

  switch (type) {
    case 'uav':
      // Broad delta silhouette: deliberately unlike a conventional aircraft.
      fillPath(
        ui.Path()
          ..moveTo(36, 15)
          ..lineTo(57, 49)
          ..lineTo(43, 44)
          ..lineTo(40, 57)
          ..lineTo(32, 57)
          ..lineTo(29, 44)
          ..lineTo(15, 49)
          ..close(),
      );
      break;
    case 'fpv':
      // Quadcopter with four visible rotors.
      for (final pair in const [
        [ui.Offset(31, 31), ui.Offset(22, 22)],
        [ui.Offset(41, 31), ui.Offset(50, 22)],
        [ui.Offset(31, 41), ui.Offset(22, 50)],
        [ui.Offset(41, 41), ui.Offset(50, 50)],
      ]) {
        line(pair[0], pair[1], width: 4);
      }
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
          const ui.Rect.fromLTWH(29, 29, 14, 14),
          const ui.Radius.circular(4),
        ),
        white,
      );
      for (final center in const [
        ui.Offset(20, 20),
        ui.Offset(52, 20),
        ui.Offset(20, 52),
        ui.Offset(52, 52),
      ]) {
        canvas.drawCircle(center, 6, whiteStroke);
        canvas.drawCircle(center, 1.8, white);
      }
      break;
    case 'recon':
      // Eye/radar pictogram keeps reconnaissance visually separate from aircraft.
      strokePath(
        ui.Path()
          ..moveTo(15, 36)
          ..quadraticBezierTo(25, 22, 36, 22)
          ..quadraticBezierTo(47, 22, 57, 36)
          ..quadraticBezierTo(47, 50, 36, 50)
          ..quadraticBezierTo(25, 50, 15, 36)
          ..close(),
      );
      canvas.drawCircle(const ui.Offset(36, 36), 7, white);
      canvas.drawCircle(
        const ui.Offset(36, 36),
        3,
        ui.Paint()..color = const ui.Color(0xff1a1f24),
      );
      break;
    case 'missile':
      // Winged cruise-missile silhouette.
      fillPath(
        ui.Path()
          ..moveTo(36, 13)
          ..quadraticBezierTo(41, 18, 40, 28)
          ..lineTo(40, 31)
          ..lineTo(56, 39)
          ..lineTo(40, 40)
          ..lineTo(40, 53)
          ..lineTo(47, 59)
          ..lineTo(38, 57)
          ..lineTo(36, 62)
          ..lineTo(34, 57)
          ..lineTo(25, 59)
          ..lineTo(32, 53)
          ..lineTo(32, 40)
          ..lineTo(16, 39)
          ..lineTo(32, 31)
          ..lineTo(32, 28)
          ..quadraticBezierTo(31, 18, 36, 13)
          ..close(),
      );
      break;
    case 'ballistic':
      // Slim rocket with small tail fins; no wings, so it reads differently
      // from the cruise-missile icon even at small map sizes.
      fillPath(
        ui.Path()
          ..moveTo(36, 12)
          ..quadraticBezierTo(42, 19, 41, 31)
          ..lineTo(40, 52)
          ..lineTo(47, 59)
          ..lineTo(40, 57)
          ..lineTo(36, 64)
          ..lineTo(32, 57)
          ..lineTo(25, 59)
          ..lineTo(32, 52)
          ..lineTo(31, 31)
          ..quadraticBezierTo(30, 19, 36, 12)
          ..close(),
      );
      line(const ui.Offset(30, 47), const ui.Offset(42, 47), width: 3);
      break;
    case 'kab':
      // Bomb body with a rounded nose and four tail fins.
      fillPath(
        ui.Path()
          ..moveTo(36, 17)
          ..quadraticBezierTo(45, 24, 44, 38)
          ..quadraticBezierTo(43, 51, 36, 59)
          ..quadraticBezierTo(29, 51, 28, 38)
          ..quadraticBezierTo(27, 24, 36, 17)
          ..close(),
      );
      fillPath(
        ui.Path()
          ..moveTo(31, 20)
          ..lineTo(23, 15)
          ..lineTo(27, 27)
          ..lineTo(31, 29)
          ..close(),
      );
      fillPath(
        ui.Path()
          ..moveTo(41, 20)
          ..lineTo(49, 15)
          ..lineTo(45, 27)
          ..lineTo(41, 29)
          ..close(),
      );
      line(const ui.Offset(31, 34), const ui.Offset(41, 34), width: 3);
      break;
    case 'mig31k':
      // Only this class uses a conventional jet silhouette.
      fillPath(
        ui.Path()
          ..moveTo(36, 11)
          ..quadraticBezierTo(40, 17, 40, 28)
          ..lineTo(59, 40)
          ..lineTo(42, 39)
          ..lineTo(41, 51)
          ..lineTo(50, 58)
          ..lineTo(40, 55)
          ..lineTo(36, 62)
          ..lineTo(32, 55)
          ..lineTo(22, 58)
          ..lineTo(31, 51)
          ..lineTo(30, 39)
          ..lineTo(13, 40)
          ..lineTo(32, 28)
          ..quadraticBezierTo(32, 17, 36, 11)
          ..close(),
      );
      break;
    default:
      // Unknown threat: neutral warning mark.
      line(const ui.Offset(36, 24), const ui.Offset(36, 43), width: 5);
      canvas.drawCircle(const ui.Offset(36, 51), 3.4, white);
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(outputSize.ceil(), outputSize.ceil());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  if (bytes == null) throw StateError('Nie udało się utworzyć ikony NEPTUN');
  return bytes.buffer.asUint8List();
}

Future<void> _registerNeptunMapIcons(
  MapLibreMapController controller,
  double pixelRatio,
) async {
  for (final type in _neptunIconTypes) {
    await controller.addImage(
      neptunMapIconId(type),
      await neptunIconPng(type, pixelRatio: pixelRatio),
    );
  }
}

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
      debugPrint('NEPTUN native tap: $point');
      final features = await c.queryRenderedFeatures(point, const [
        'neptun-live-groups',
        'neptun-live-group-counts',
        'neptun-live-symbols',
        'neptun-live-hit-points',
      ], null);
      if (!mounted || features.isEmpty) return;
      final candidates = <String, Map<String, dynamic>>{};
      for (final feature in features.whereType<Map>()) {
        final properties = feature['properties'];
        final leaves = properties is Map && properties['cluster'] == true
            ? await c.getClusterLeaves(
                'neptun-live',
                (properties['cluster_id'] as num).toInt(),
                limit: (properties['point_count'] as num).toInt(),
              )
            : [feature];
        for (final leaf in leaves) {
          final item = neptunThreatForFeature(widget.data, leaf);
          if (item != null) candidates[item['id'] as String] = item;
        }
      }
      if (!mounted || candidates.isEmpty) return;
      debugPrint('NEPTUN selected entries: ${candidates.length}');
      Map<String, dynamic>? threat;
      if (candidates.length == 1) {
        threat = candidates.values.single;
      } else {
        threat = await showModalBottomSheet<Map<String, dynamic>>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (sheetContext) => SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.65,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '${candidates.length} wpisów w tym obszarze',
                      style: Theme.of(sheetContext).textTheme.titleLarge,
                    ),
                  ),
                  for (final item in candidates.values)
                    ListTile(
                      title: Text(item['title'] as String),
                      subtitle: Text(neptunTypeLabel(item['type'] as String)),
                      onTap: () => Navigator.pop(sheetContext, item),
                    ),
                ],
              ),
            ),
          ),
        );
      }
      if (!mounted) return;
      if (threat == null) return;
      final selectedThreat = threat;
      final location = (selectedThreat['region'] as String?)?.trim() ?? '';
      final precision = selectedThreat['precisionKm'];
      final sourceCount = selectedThreat['sourceCount'];
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
                    FutureBuilder<Uint8List>(
                      future: neptunIconPng(
                        selectedThreat['type'] as String,
                        pixelRatio: MediaQuery.devicePixelRatioOf(sheetContext),
                      ),
                      builder: (context, snapshot) => snapshot.hasData
                          ? Image.memory(
                              snapshot.data!,
                              width: 36,
                              height: 36,
                              filterQuality: FilterQuality.high,
                            )
                          : const SizedBox(
                              width: 36,
                              height: 36,
                              child: Icon(Icons.flight_outlined),
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        selectedThreat['title'] as String,
                        style: Theme.of(sheetContext).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Typ: ${neptunTypeLabel(selectedThreat['type'] as String)}',
                ),
                if (location.isNotEmpty) Text('Obszar: $location'),
                Text(
                  'Status: ${selectedThreat['status'] == 'active' ? 'aktywny' : 'nieaktualny / STALE'}',
                ),
                Text(
                  'Aktualizacja: ${stamp(selectedThreat['updatedAt'] as String)}',
                ),
                Text(
                  'Pewność: ${confidenceLabel(selectedThreat['confidenceLevel'])}'
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
    } catch (error) {
      debugPrint('NEPTUN map tap failed: $error');
      // A tap must never break map interaction if the style is reloading.
    }
  }

  Future<void> styled() async {
    if (!mounted) return;
    final c = controller;
    if (c == null) return;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    try {
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
      await c.addSource(
        'neptun-live',
        GeojsonSourceProperties(
          // Populate only after images and symbol layers have been registered.
          data: {'type': 'FeatureCollection', 'features': []},
          cluster: true,
          clusterRadius: 48,
          clusterMaxZoom: 16,
        ),
      );
      await _registerNeptunMapIcons(c, pixelRatio);
      await c.addCircleLayer(
        'neptun-live',
        'neptun-live-hit-points',
        const CircleLayerProperties(
          circleColor: '#000000',
          circleRadius: 22,
          circleOpacity: 0.001,
        ),
        filter: [
          '!',
          ['has', 'point_count'],
        ],
      );
      await c.addSymbolLayer(
        'neptun-live',
        'neptun-live-symbols',
        const SymbolLayerProperties(
          iconImage: [
            'match',
            ['get', 'type'],
            'uav',
            'neptun-icon-uav',
            'fpv',
            'neptun-icon-fpv',
            'recon',
            'neptun-icon-recon',
            'missile',
            'neptun-icon-missile',
            'ballistic',
            'neptun-icon-ballistic',
            'kab',
            'neptun-icon-kab',
            'mig31k',
            'neptun-icon-mig31k',
            'neptun-icon-unknown',
          ],
          iconSize: 1,
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
          iconAnchor: 'center',
        ),
        filter: [
          '!',
          ['has', 'point_count'],
        ],
      );
      await c.addCircleLayer(
        'neptun-live',
        'neptun-live-groups',
        const CircleLayerProperties(
          circleColor: '#263238',
          circleRadius: 19,
          circleStrokeColor: '#ffffff',
          circleStrokeWidth: 2,
        ),
        filter: ['has', 'point_count'],
      );
      await c.addSymbolLayer(
        'neptun-live',
        'neptun-live-group-counts',
        const SymbolLayerProperties(
          textField: [
            'to-string',
            ['get', 'point_count'],
          ],
          textFont: ['Noto Sans Regular'],
          textSize: 16,
          textColor: '#ffffff',
          textAllowOverlap: true,
          textIgnorePlacement: true,
        ),
        filter: ['has', 'point_count'],
      );
      ready = true;
      await syncSources();
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
        'Liczba na znaczniku oznacza grupę wpisów — dotknij, aby wybrać wpis. ',
      ),
      const Text(
        'Kolor obwódki i kształt oznaczają typ: pomarańczowy — dron/FPV, niebieski — rozpoznanie, czerwony — rakieta, różowy — balistyka, ceglasty — KAB, fioletowy — MiG-31K. Ikony są zawsze ustawione pionowo i nie pokazują kierunku lotu. Pozycje pozostają celowo zgrubne. Fioletowe linie: wyłącznie historia.',
      ),
      if (error != null) Text(error!),
    ],
  );
}
