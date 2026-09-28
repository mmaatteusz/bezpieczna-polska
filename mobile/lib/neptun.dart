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

Future<Uint8List> _neptunIconPng(String type) async {
  // Render on a larger backing image so threat symbols stay crisp on
  // high-density Android displays. The geometry below uses a 72x72
  // logical grid and is scaled only at rasterization time.
  const logicalSize = 72.0;
  const outputSize = 96.0;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..scale(outputSize / logicalSize);
  final outline = ui.Paint()
    ..color = const ui.Color(0xff7f1d1d)
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 6
    ..strokeJoin = ui.StrokeJoin.round
    ..strokeCap = ui.StrokeCap.round;
  final fill = ui.Paint()
    ..color = const ui.Color(0xffffffff)
    ..style = ui.PaintingStyle.fill;
  final whiteStroke = ui.Paint()
    ..color = const ui.Color(0xffffffff)
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 6
    ..strokeJoin = ui.StrokeJoin.round
    ..strokeCap = ui.StrokeCap.round;

  void paintPath(ui.Path path) {
    canvas.drawPath(path, outline);
    canvas.drawPath(path, fill);
  }

  ui.Path aircraft({
    required double wingY,
    required double wingSpan,
    required double tailSpan,
    double noseY = 7,
    double tailY = 61,
  }) {
    return ui.Path()
      ..moveTo(36, noseY)
      ..lineTo(41, wingY - 5)
      ..lineTo(36 + wingSpan, wingY + 7)
      ..lineTo(39, wingY + 9)
      ..lineTo(40, tailY - 9)
      ..lineTo(36 + tailSpan, tailY - 2)
      ..lineTo(36, tailY - 5)
      ..lineTo(36 - tailSpan, tailY - 2)
      ..lineTo(32, tailY - 9)
      ..lineTo(33, wingY + 9)
      ..lineTo(36 - wingSpan, wingY + 7)
      ..lineTo(31, wingY - 5)
      ..close();
  }

  switch (type) {
    case 'uav':
      // A classic top-view quadcopter silhouette is intentionally used here
      // instead of a delta/arrow outline. At map scale the old silhouette
      // was too easy to read as a mouse cursor.
      final armOutline = ui.Paint()
        ..color = const ui.Color(0xff7f1d1d)
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = ui.StrokeCap.round;
      final armFill = ui.Paint()
        ..color = const ui.Color(0xffffffff)
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = ui.StrokeCap.round;
      for (final pair in const [
        [ui.Offset(31, 31), ui.Offset(18, 18)],
        [ui.Offset(41, 31), ui.Offset(54, 18)],
        [ui.Offset(31, 41), ui.Offset(18, 54)],
        [ui.Offset(41, 41), ui.Offset(54, 54)],
      ]) {
        canvas.drawLine(pair[0], pair[1], armOutline);
        canvas.drawLine(pair[0], pair[1], armFill);
      }
      for (final center in const [
        ui.Offset(16, 16),
        ui.Offset(56, 16),
        ui.Offset(16, 56),
        ui.Offset(56, 56),
      ]) {
        canvas.drawCircle(center, 9.5, outline);
        canvas.drawCircle(center, 7.5, fill);
      }
      final body = ui.RRect.fromRectAndRadius(
        const ui.Rect.fromLTWH(27, 25, 18, 22),
        const ui.Radius.circular(6),
      );
      canvas.drawRRect(body, outline);
      canvas.drawRRect(body, fill);
      canvas.drawCircle(const ui.Offset(36, 31), 3, outline);
      canvas.drawCircle(const ui.Offset(36, 31), 1.5, fill);
      break;
    case 'fpv':
      final armOutline = ui.Paint()
        ..color = const ui.Color(0xff7f1d1d)
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 11
        ..strokeCap = ui.StrokeCap.round;
      canvas.drawLine(
        const ui.Offset(20, 20),
        const ui.Offset(52, 52),
        armOutline,
      );
      canvas.drawLine(
        const ui.Offset(52, 20),
        const ui.Offset(20, 52),
        armOutline,
      );
      canvas.drawLine(
        const ui.Offset(20, 20),
        const ui.Offset(52, 52),
        whiteStroke,
      );
      canvas.drawLine(
        const ui.Offset(52, 20),
        const ui.Offset(20, 52),
        whiteStroke,
      );
      for (final center in const [
        ui.Offset(17, 17),
        ui.Offset(55, 17),
        ui.Offset(17, 55),
        ui.Offset(55, 55),
      ]) {
        canvas.drawCircle(center, 8, outline);
        canvas.drawCircle(center, 7, fill);
      }
      canvas.drawCircle(const ui.Offset(36, 36), 9, outline);
      canvas.drawCircle(const ui.Offset(36, 36), 8, fill);
      break;
    case 'recon':
      paintPath(aircraft(wingY: 31, wingSpan: 25, tailSpan: 10));
      break;
    case 'missile':
      paintPath(
        ui.Path()
          ..moveTo(36, 6)
          ..quadraticBezierTo(45, 16, 44, 29)
          ..lineTo(43, 49)
          ..lineTo(55, 61)
          ..lineTo(42, 57)
          ..lineTo(36, 66)
          ..lineTo(30, 57)
          ..lineTo(17, 61)
          ..lineTo(29, 49)
          ..lineTo(28, 29)
          ..quadraticBezierTo(27, 16, 36, 6)
          ..close(),
      );
      break;
    case 'ballistic':
      paintPath(
        ui.Path()
          ..moveTo(36, 5)
          ..quadraticBezierTo(47, 17, 45, 33)
          ..lineTo(43, 48)
          ..lineTo(54, 57)
          ..lineTo(43, 55)
          ..lineTo(36, 66)
          ..lineTo(29, 55)
          ..lineTo(18, 57)
          ..lineTo(29, 48)
          ..lineTo(27, 33)
          ..quadraticBezierTo(25, 17, 36, 5)
          ..close(),
      );
      canvas.drawLine(
        const ui.Offset(27, 66),
        const ui.Offset(21, 71),
        whiteStroke,
      );
      canvas.drawLine(
        const ui.Offset(45, 66),
        const ui.Offset(51, 71),
        whiteStroke,
      );
      break;
    case 'kab':
      paintPath(
        ui.Path()
          ..moveTo(36, 8)
          ..quadraticBezierTo(51, 19, 47, 42)
          ..quadraticBezierTo(44, 55, 36, 61)
          ..quadraticBezierTo(28, 55, 25, 42)
          ..quadraticBezierTo(21, 19, 36, 8)
          ..close(),
      );
      paintPath(
        ui.Path()
          ..moveTo(29, 52)
          ..lineTo(17, 65)
          ..lineTo(31, 61)
          ..lineTo(36, 68)
          ..lineTo(41, 61)
          ..lineTo(55, 65)
          ..lineTo(43, 52)
          ..close(),
      );
      break;
    case 'mig31k':
      paintPath(aircraft(wingY: 33, wingSpan: 28, tailSpan: 13, tailY: 64));
      break;
    default:
      paintPath(
        ui.Path()
          ..moveTo(36, 8)
          ..lineTo(63, 36)
          ..lineTo(36, 64)
          ..lineTo(9, 36)
          ..close(),
      );
      canvas.drawLine(
        const ui.Offset(36, 22),
        const ui.Offset(36, 43),
        whiteStroke,
      );
      canvas.drawCircle(const ui.Offset(36, 52), 3.5, fill);
  }

  final image = await recorder.endRecording().toImage(
    outputSize.toInt(),
    outputSize.toInt(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (bytes == null) throw StateError('Nie udało się utworzyć ikony NEPTUN');
  return bytes.buffer.asUint8List();
}

Future<void> _registerNeptunMapIcons(MapLibreMapController controller) async {
  for (final type in _neptunIconTypes) {
    await controller.addImage(
      neptunMapIconId(type),
      await _neptunIconPng(type),
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
      final features = await c.queryRenderedFeatures(point, const [
        'neptun-live-symbols',
        'neptun-live-hit-points',
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
                    FutureBuilder<Uint8List>(
                      future: _neptunIconPng(threat['type'] as String),
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
      await _registerNeptunMapIcons(c);
      await c.addCircleLayer(
        'neptun-live',
        'neptun-live-hit-points',
        const CircleLayerProperties(
          circleColor: '#000000',
          circleRadius: 22,
          circleOpacity: 0.001,
        ),
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
          iconSize: 0.66,
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
          iconAnchor: 'center',
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
        'Białe symbole pokazują typ zagrożenia (np. dron, FPV, rakieta, KAB, MiG-31K). Ich orientacja jest wyłącznie graficzna i nie oznacza kierunku lotu. Pozycje pozostają celowo zgrubne. Fioletowe linie: wyłącznie historia.',
      ),
      if (error != null) Text(error!),
    ],
  );
}
