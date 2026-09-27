import 'package:flutter/material.dart';

abstract final class BrandColors {
  static const navy = Color(0xFF071B2A);
  static const navySoft = Color(0xFF102D40);
  static const polishRed = Color(0xFFD4213D);
  static const offWhite = Color(0xFFFAFAF8);
  static const mist = Color(0xFFC8D6DF);
  static const logoBackground = Color(0xFF000000);
}

class BrandMark extends StatelessWidget {
  final double size;
  final String? semanticLabel;
  final BoxFit fit;

  const BrandMark({
    super.key,
    this.size = 96,
    this.semanticLabel,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Image.asset(
      'assets/brand/bezpieczna_polska_logo_transparent.png',
      width: size,
      height: size,
      fit: fit,
      filterQuality: FilterQuality.high,
      semanticLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    ),
  );
}
