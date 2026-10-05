import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

double shelterClusterDiameter(int count) => count < 100
    ? 32
    : count < 1000
    ? 36
    : count < 10000
    ? 40
    : 44;

/// Merge neighbouring server grid cells in screen space without losing counts.
/// Mercator distances are logical map pixels, independent of screen density.
List<Map<String, dynamic>> shelterDisplayFeatures(List features, double zoom) {
  final points = <Map<String, dynamic>>[];
  final groups = <_ShelterGroup>[];
  final world = (512 * math.pow(2, zoom)).toDouble();
  for (final raw in features.whereType<Map>()) {
    final feature = Map<String, dynamic>.from(raw);
    final p = feature['properties'] as Map;
    if (p['cluster'] != true) {
      points.add(feature);
      continue;
    }
    final coordinates = feature['geometry']['coordinates'] as List;
    final latitude = (coordinates[1] as num).toDouble().clamp(
      -85.05112878,
      85.05112878,
    );
    final sin = math.sin(latitude * math.pi / 180);
    var group = _ShelterGroup(
      feature,
      (p['point_count'] as num).toInt(),
      ((coordinates[0] as num).toDouble() + 180) / 360 * world,
      (0.5 - math.log((1 + sin) / (1 - sin)) / (4 * math.pi)) * world,
      (p['expansionZoom'] as num?)?.toDouble() ?? zoom + 1,
    );
    // Recheck after moving the weighted centroid: merging can touch another cell.
    while (true) {
      final index = groups.indexWhere((other) {
        final distance = math.sqrt(
          math.pow(group.x - other.x, 2) + math.pow(group.y - other.y, 2),
        );
        return distance <
            (shelterClusterDiameter(group.count) +
                        shelterClusterDiameter(other.count)) /
                    2 +
                6;
      });
      if (index < 0) break;
      group = group.merge(groups.removeAt(index));
    }
    groups.add(group);
  }
  return [
    ...points,
    for (final group in groups)
      {
        ...group.feature,
        'geometry': {
          'type': 'Point',
          'coordinates': [
            group.x / world * 360 - 180,
            math.atan(math.exp(math.pi * (1 - 2 * group.y / world))) *
                    360 /
                    math.pi -
                90,
          ],
        },
        'properties': {
          ...group.feature['properties'] as Map,
          'point_count': group.count,
          'expansionZoom': math.min(
            22.0,
            math.max(zoom + 1, group.expansionZoom),
          ),
        },
      },
  ];
}

class _ShelterGroup {
  final Map<String, dynamic> feature;
  final int count;
  final double x, y, expansionZoom;
  _ShelterGroup(this.feature, this.count, this.x, this.y, this.expansionZoom);

  _ShelterGroup merge(_ShelterGroup other) {
    final total = count + other.count;
    return _ShelterGroup(
      feature,
      total,
      (x * count + other.x * other.count) / total,
      (y * count + other.y * other.count) / total,
      math.max(expansionZoom, other.expansionZoom),
    );
  }
}

/// One native icon keeps the background, count and touch target at one scale.
/// MapLibre decodes images at device density; rasterise at the same density and
/// use iconSize=1 rather than shrinking a separate two-times count bitmap.
Future<Uint8List> shelterClusterImage(int count, double pixelRatio) async {
  final diameter = shelterClusterDiameter(count);
  final painter = TextPainter(
    text: TextSpan(
      text: '$count',
      style: TextStyle(
        fontSize: count < 10000 ? 14 : 12,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(pixelRatio);
  final center = Offset(diameter / 2, diameter / 2);
  canvas.drawCircle(
    center,
    diameter / 2 - 1,
    Paint()..color = const Color(0xff2e7d32),
  );
  canvas.drawCircle(
    center,
    diameter / 2 - 1,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5,
  );
  painter.paint(
    canvas,
    Offset((diameter - painter.width) / 2, (diameter - painter.height) / 2),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (diameter * pixelRatio).ceil(),
    (diameter * pixelRatio).ceil(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  painter.dispose();
  if (bytes == null) throw StateError('Brak obrazu grupy schronień');
  return bytes.buffer.asUint8List();
}
