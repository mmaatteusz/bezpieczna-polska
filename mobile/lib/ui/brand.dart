import 'package:flutter/material.dart';

abstract final class BrandColors {
  static const navy = Color(0xFF071B2A);
  static const navySoft = Color(0xFF102D40);
  static const polishRed = Color(0xFFD4213D);
  static const offWhite = Color(0xFFFAFAF8);
  static const mist = Color(0xFFC8D6DF);
}

class BrandMark extends StatelessWidget {
  final double size;
  final String? semanticLabel;

  const BrandMark({super.key, this.size = 96, this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    final mark = CustomPaint(
      size: Size.square(size),
      painter: const _BrandMarkPainter(),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: mark);
    return Semantics(label: semanticLabel, image: true, child: mark);
  }
}

class _BrandMarkPainter extends CustomPainter {
  const _BrandMarkPainter();

  Path _shield(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(w * 0.20, h * 0.14)
      ..quadraticBezierTo(w * 0.50, h * 0.04, w * 0.80, h * 0.14)
      ..lineTo(w * 0.77, h * 0.53)
      ..quadraticBezierTo(w * 0.73, h * 0.72, w * 0.50, h * 0.90)
      ..quadraticBezierTo(w * 0.27, h * 0.72, w * 0.23, h * 0.53)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final shield = _shield(size);

    canvas.save();
    canvas.clipPath(shield);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height * 0.50),
      Paint()..color = BrandColors.offWhite,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        0,
        size.height * 0.50,
        size.width,
        size.height * 0.50,
      ),
      Paint()..color = BrandColors.polishRed,
    );
    canvas.restore();

    canvas.drawPath(
      shield,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.038
        ..strokeJoin = StrokeJoin.round
        ..color = BrandColors.mist,
    );

    final seam = Path()
      ..moveTo(size.width * 0.235, size.height * 0.50)
      ..lineTo(size.width * 0.765, size.height * 0.50);
    canvas.drawPath(
      seam,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.018
        ..strokeCap = StrokeCap.round
        ..color = BrandColors.navy.withAlpha(95),
    );
  }

  @override
  bool shouldRepaint(covariant _BrandMarkPainter oldDelegate) => false;
}
