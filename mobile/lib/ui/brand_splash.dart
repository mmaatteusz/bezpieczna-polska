import 'package:flutter/material.dart';

import 'brand.dart';

class BrandLoadingScreen extends StatelessWidget {
  const BrandLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: BrandColors.navy,
    body: SafeArea(
      child: Center(
        child: Semantics(
          label:
              'Bezpieczna Polska. Najważniejsze jest Twoje bezpieczeństwo. Ładowanie aplikacji.',
          container: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BrandMark(size: 112),
                const SizedBox(height: 24),
                const Text(
                  'Najważniejsze jest Twoje bezpieczeństwo',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: BrandColors.offWhite,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 180,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: const LinearProgressIndicator(
                      minHeight: 3,
                      color: BrandColors.polishRed,
                      backgroundColor: Color(0x33FFFFFF),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'BEZPIECZNA POLSKA',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: BrandColors.mist,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
