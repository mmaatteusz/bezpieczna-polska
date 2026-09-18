import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'model.dart';

class SafetyMap extends StatefulWidget {
  final List<SafetyEvent> events;
  final bool ukraine;
  const SafetyMap({super.key, required this.events, required this.ukraine});
  @override
  State<SafetyMap> createState() => _SafetyMapState();
}

class _SafetyMapState extends State<SafetyMap> {
  late final Future<Map<String, dynamic>> countries;
  @override
  void initState() {
    super.initState();
    countries = rootBundle
        .loadString('assets/europe.geojson')
        .then((s) => Map<String, dynamic>.from(jsonDecode(s) as Map));
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Mapa poglądowa. Komunikaty dostępne są także na liście.',
    child: FutureBuilder<Map<String, dynamic>>(
      future: countries,
      builder: (context, result) {
        if (result.hasError) {
          return const Center(
            child: Text('Nie udało się odczytać mapy offline.'),
          );
        }
        if (!result.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return LayoutBuilder(
          builder: (context, box) => InteractiveViewer(
            maxScale: 5,
            child: CustomPaint(
              size: Size(box.maxWidth, box.maxHeight),
              painter: _Painter(result.data!, widget.events, widget.ukraine),
            ),
          ),
        );
      },
    ),
  );
}

class _Painter extends CustomPainter {
  final Map<String, dynamic> data;
  final List<SafetyEvent> events;
  final bool ua;
  _Painter(this.data, this.events, this.ua);
  @override
  void paint(Canvas c, Size size) {
    c.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF182C38));
    c.save();
    c.clipRect(Offset.zero & size);
    final minLon = ua ? 20.0 : 12.0,
        maxLon = ua ? 42.0 : 26.0,
        minLat = ua ? 43.0 : 48.0,
        maxLat = ua ? 54.0 : 56.5;
    Offset project(num x, num y) => Offset(
      (x - minLon) / (maxLon - minLon) * size.width,
      (maxLat - y) / (maxLat - minLat) * size.height,
    );
    for (final raw in data['features'] as List) {
      final f = raw as Map, g = f['geometry'] as Map;
      final list = g['type'] == 'Polygon'
          ? [g['coordinates']]
          : g['coordinates'] as List;
      for (final poly in list) {
        final path = Path()..fillType = PathFillType.evenOdd;
        for (final ring in poly as List) {
          final points = ring as List;
          for (var i = 0; i < points.length; i++) {
            final xy = points[i] as List,
                p = project(xy[0] as num, xy[1] as num);
            if (i == 0) {
              path.moveTo(p.dx, p.dy);
            } else {
              path.lineTo(p.dx, p.dy);
            }
          }
          path.close();
        }
        c.drawPath(
          path,
          Paint()
            ..color = f['properties']['name'] == (ua ? 'Ukraine' : 'Poland')
                ? const Color(0xFF315A59)
                : const Color(0xFF243D47),
        );
        c.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0xFF78929A),
        );
      }
    }
    for (final e in events.where((e) => e.hasPoint)) {
      final p = project(e.data['longitude'] as num, e.data['latitude'] as num);
      c.drawCircle(p, 6, Paint()..color = const Color(0xFF76C9EE));
      c.drawCircle(
        p,
        6,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    c.restore();
  }

  @override
  bool shouldRepaint(_Painter old) => old.ua != ua || old.events != events;
}
