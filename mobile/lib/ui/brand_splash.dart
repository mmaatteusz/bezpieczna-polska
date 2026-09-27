import 'package:flutter/material.dart';

import 'brand.dart';

class BrandSplashGate extends StatefulWidget {
  final Widget child;

  const BrandSplashGate({super.key, required this.child});

  @override
  State<BrandSplashGate> createState() => _BrandSplashGateState();
}

class _BrandSplashGateState extends State<BrandSplashGate>
    with SingleTickerProviderStateMixin {
  static const _startupDuration = Duration(milliseconds: 1650);

  late final AnimationController _controller;
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: _startupDuration,
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            setState(() => _showSplash = false);
          }
        });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _segment(double value, double start, double end) {
    final normalized = ((value - start) / (end - start))
        .clamp(0.0, 1.0)
        .toDouble();
    return Curves.easeOutCubic.transform(normalized);
  }

  @override
  Widget build(BuildContext context) {
    if (!_showSplash) return widget.child;

    return ColoredBox(
      color: BrandColors.navy,
      child: SafeArea(
        child: Center(
          child: Semantics(
            label:
                'Bezpieczna Polska. Najważniejsze jest Twoje bezpieczeństwo. Ładowanie aplikacji.',
            container: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final value = _controller.value;
                  final reduceMotion =
                      MediaQuery.maybeOf(context)?.disableAnimations ?? false;
                  final enter = _segment(value, 0.02, 0.30);
                  final copy = _segment(value, 0.12, 0.38);
                  final detail = _segment(value, 0.20, 0.48);
                  final progress = _segment(value, 0.10, 0.96);

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Opacity(
                        opacity: enter,
                        child: Transform.translate(
                          offset: Offset(
                            0,
                            reduceMotion ? 0 : 14 * (1 - enter),
                          ),
                          child: Transform.scale(
                            scale: reduceMotion ? 1 : 0.90 + (0.10 * enter),
                            child: const BrandMark(size: 112),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Opacity(
                        opacity: copy,
                        child: const Text(
                          'BEZPIECZNA POLSKA',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: BrandColors.offWhite,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1,
                            height: 1.05,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Opacity(
                        opacity: detail,
                        child: const Text(
                          'Najważniejsze jest Twoje bezpieczeństwo',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: BrandColors.mist,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.1,
                            height: 1.25,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Opacity(
                        opacity: detail,
                        child: SizedBox(
                          width: 220,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 5,
                              backgroundColor: BrandColors.navySoft,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                BrandColors.polishRed,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Opacity(
                        opacity: detail,
                        child: const Text(
                          'Ładowanie aplikacji…',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: BrandColors.mist,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.15,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
