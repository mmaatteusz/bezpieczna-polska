import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model.dart';

class ProvinceOutline extends StatelessWidget {
  final String? region;

  const ProvinceOutline({super.key, required this.region});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: 116,
      height: 104,
      child: FutureBuilder<Map<String, Path>>(
        future: rootBundle.loadStructuredData(
          'assets/poland_voivodeships_min.geojson',
          _readProvinces,
        ),
        builder: (context, snapshot) => CustomPaint(
          painter: snapshot.hasData
              ? _ProvincePainter(snapshot.data!, regions[region]?.toLowerCase())
              : null,
        ),
      ),
    ),
  );
}

Future<Map<String, Path>> _readProvinces(String source) async {
  final data = jsonDecode(source) as Map<String, dynamic>;
  return {
    for (final feature in data['features'] as List)
      feature['properties']['nazwa'] as String: _provincePath(
        feature['geometry'] as Map<String, dynamic>,
      ),
  };
}

Path _provincePath(Map<String, dynamic> geometry) {
  final coordinates = geometry['coordinates'] as List;
  final polygons = geometry['type'] == 'MultiPolygon'
      ? coordinates
      : [coordinates];
  final path = Path()..fillType = PathFillType.evenOdd;
  for (final polygon in polygons) {
    for (final ring in polygon as List) {
      path.addPolygon(
        (ring as List).map((point) {
          // Equirectangular projection, scaled at Poland's central latitude.
          return Offset(
            (point[0] as num) * 0.6157,
            -(point[1] as num).toDouble(),
          );
        }).toList(),
        true,
      );
    }
  }
  return path;
}

class _ProvincePainter extends CustomPainter {
  final Map<String, Path> provinces;
  final String? selected;

  const _ProvincePainter(this.provinces, this.selected);

  @override
  void paint(Canvas canvas, Size size) {
    if (provinces.isEmpty) return;

    final bounds = provinces.values
        .map((path) => path.getBounds())
        .reduce((a, b) => a.expandToInclude(b));
    final scale = math.min(
      (size.width - 4) / bounds.width,
      (size.height - 4) / bounds.height,
    );
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-bounds.center.dx, -bounds.center.dy);
    final fill = Paint()..color = const Color(0xFF24475D);
    final stroke = Paint()
      ..color = const Color(0xFF668496)
      ..strokeWidth = 0.8 / scale
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final province in provinces.values) {
      canvas.drawPath(province, fill);
    }
    for (final province in provinces.values) {
      canvas.drawPath(province, stroke);
    }

    final selection = provinces[selected];
    if (selection != null) {
      canvas.drawPath(selection, fill..color = const Color(0xFF8EBDCF));
      canvas.drawPath(
        selection,
        stroke
          ..color = const Color(0xFFD6EFF9)
          ..strokeWidth = 1.35 / scale,
      );
    }
  }

  @override
  bool shouldRepaint(_ProvincePainter oldDelegate) =>
      provinces != oldDelegate.provinces || selected != oldDelegate.selected;
}
