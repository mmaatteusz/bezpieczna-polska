import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

const neptunMarkerTypes = [
  'uav',
  'fpv',
  'recon',
  'missile',
  'ballistic',
  'kab',
  'mig31k',
  'unknown',
];

String neptunMapIconId(String type) =>
    'neptun-icon-${neptunMarkerTypes.contains(type) ? type : 'unknown'}';

Color neptunMarkerAccent(String type) => switch (type) {
  'uav' => const Color(0xfff4ad53),
  'fpv' => const Color(0xffffd47e),
  'recon' => const Color(0xff74cde9),
  'missile' => const Color(0xffff837c),
  'ballistic' => const Color(0xffed8bb8),
  'kab' => const Color(0xffdc9a75),
  'mig31k' => const Color(0xffbea8ff),
  _ => const Color(0xffa7b9c8),
};

Future<Uint8List> neptunIconPng(String type, {double pixelRatio = 1}) async {
  final size = (40 * pixelRatio).ceil();
  final recorder = ui.PictureRecorder();
  _MarkerPainter(type).paint(Canvas(recorder), Size.square(size.toDouble()));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(size, size);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) {
        throw StateError('Nie udało się utworzyć ikony NEPTUN');
      }
      return bytes.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

class NeptunMarkerGlyph extends StatelessWidget {
  final String type;
  final double size;

  const NeptunMarkerGlyph({super.key, required this.type, this.size = 36});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _MarkerPainter(type));
}

class _MarkerPainter extends CustomPainter {
  final String type;

  const _MarkerPainter(this.type);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 40, size.height / 40);

    final accent = neptunMarkerAccent(type);
    final paint = Paint()..color = accent;
    final badge = RRect.fromLTRBR(
      5.5,
      5.5,
      34.5,
      34.5,
      const Radius.circular(9),
    );
    canvas.drawRRect(
      badge.shift(const Offset(0, 1)),
      paint
        ..color = const Color(0xa0152029)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.8),
    );
    canvas.drawRRect(
      badge,
      paint
        ..maskFilter = null
        ..color = Color.alphaBlend(
          accent.withValues(alpha: 0.16),
          const Color(0xff16212c),
        ),
    );
    canvas.drawRRect(
      badge,
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.15
        ..color = accent,
    );

    final glyph = Paint()..color = const Color(0xfffbfcff);
    final stroke = Paint()
      ..color = glyph.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.85
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final detail = Paint()..color = accent;
    const center = Offset(20, 20);

    // Upright pictograms describe categories at a glance on both basemaps.
    switch (type) {
      case 'uav':
        canvas.drawPath(
          Path()
            ..moveTo(20, 10)
            ..quadraticBezierTo(22.1, 10, 22.8, 15)
            ..lineTo(30.7, 18.1)
            ..lineTo(30.7, 21.6)
            ..lineTo(22.4, 20.6)
            ..lineTo(22.3, 25.8)
            ..lineTo(26, 27.2)
            ..lineTo(26, 29.7)
            ..lineTo(20, 28.7)
            ..lineTo(14, 29.7)
            ..lineTo(14, 27.2)
            ..lineTo(17.7, 25.8)
            ..lineTo(17.6, 20.6)
            ..lineTo(9.3, 21.6)
            ..lineTo(9.3, 18.1)
            ..lineTo(17.2, 15)
            ..quadraticBezierTo(17.9, 10, 20, 10)
            ..close(),
          glyph,
        );
      case 'fpv':
        for (final rotor in const [
          Offset(12.6, 12.6),
          Offset(27.4, 12.6),
          Offset(12.6, 27.4),
          Offset(27.4, 27.4),
        ]) {
          canvas.drawLine(center, Offset.lerp(center, rotor, 0.71)!, stroke);
          canvas.drawCircle(rotor, 2.9, stroke);
          canvas.drawCircle(rotor, 0.85, detail);
        }
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: center, width: 8, height: 8),
            const Radius.circular(2.3),
          ),
          glyph,
        );
      case 'recon':
        canvas.drawPath(
          Path()
            ..moveTo(10, 20)
            ..quadraticBezierTo(20, 7.5, 30, 20)
            ..quadraticBezierTo(20, 32.5, 10, 20)
            ..close(),
          stroke,
        );
        canvas.drawCircle(center, 3.4, glyph);
        canvas.drawCircle(center, 1.65, detail);
      case 'missile':
        canvas.drawPath(
          Path()
            ..moveTo(20, 8.8)
            ..quadraticBezierTo(23.2, 11, 23, 15.4)
            ..lineTo(23, 17.5)
            ..lineTo(29.1, 22.4)
            ..lineTo(23, 23)
            ..lineTo(23, 26.8)
            ..lineTo(25.3, 29.7)
            ..lineTo(14.7, 29.7)
            ..lineTo(17, 26.8)
            ..lineTo(17, 23)
            ..lineTo(10.9, 22.4)
            ..lineTo(17, 17.5)
            ..lineTo(17, 15.4)
            ..quadraticBezierTo(16.8, 11, 20, 8.8)
            ..close(),
          glyph,
        );
        canvas.drawRect(const Rect.fromLTWH(17, 23.9, 6, 1.5), detail);
      case 'ballistic':
        canvas.drawPath(
          Path()
            ..moveTo(20, 8.7)
            ..quadraticBezierTo(23.8, 11.7, 23.4, 17)
            ..lineTo(23.2, 25.6)
            ..lineTo(25.5, 30)
            ..lineTo(20, 28.4)
            ..lineTo(14.5, 30)
            ..lineTo(16.8, 25.6)
            ..lineTo(16.6, 17)
            ..quadraticBezierTo(16.2, 11.7, 20, 8.7)
            ..close(),
          glyph,
        );
        canvas.drawRect(const Rect.fromLTWH(16.9, 20.6, 6.2, 2), detail);
      case 'kab':
        canvas.drawPath(
          Path()
            ..moveTo(14, 11)
            ..lineTo(17.7, 12.6)
            ..lineTo(22.3, 12.6)
            ..lineTo(26, 11)
            ..lineTo(24.2, 18)
            ..quadraticBezierTo(26, 25.8, 20, 30)
            ..quadraticBezierTo(14, 25.8, 15.8, 18)
            ..close(),
          glyph,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(16, 18, 8, 2.4),
            const Radius.circular(1.2),
          ),
          detail,
        );
      case 'mig31k':
        canvas.drawPath(
          Path()
            ..moveTo(20, 8.7)
            ..quadraticBezierTo(22.1, 10.2, 22.4, 15.2)
            ..lineTo(29.9, 23.2)
            ..lineTo(23.1, 22.2)
            ..lineTo(22.8, 26.5)
            ..lineTo(26, 30.6)
            ..lineTo(20, 28.5)
            ..lineTo(14, 30.6)
            ..lineTo(17.2, 26.5)
            ..lineTo(16.9, 22.2)
            ..lineTo(10.1, 23.2)
            ..lineTo(17.6, 15.2)
            ..quadraticBezierTo(17.9, 10.2, 20, 8.7)
            ..close(),
          glyph,
        );
        canvas.drawCircle(const Offset(20, 15), 1.2, detail);
      default:
        canvas.drawPath(
          Path()
            ..moveTo(20, 10.4)
            ..lineTo(29.6, 20)
            ..lineTo(20, 29.6)
            ..lineTo(10.4, 20)
            ..close(),
          stroke,
        );
        canvas.drawLine(const Offset(20, 15.4), const Offset(20, 20.7), stroke);
        canvas.drawCircle(const Offset(20, 24), 1.1, glyph);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkerPainter oldDelegate) => oldDelegate.type != type;
}
