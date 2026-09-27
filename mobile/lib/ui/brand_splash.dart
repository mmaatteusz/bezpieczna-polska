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
  late final AnimationController _controller;
  bool _showOverlay = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _showOverlay = false);
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
    final normalized = ((value - start) / (end - start)).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(normalized);
  }

  @override
  Widget build(BuildContext context) {
    if (!_showOverlay) return widget.child;

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final value = _controller.value;
              final reduceMotion =
                  MediaQuery.maybeOf(context)?.disableAnimations ?? false;
              final enter = _segment(value, 0.02, 0.36);
              final copy = _segment(value, 0.18, 0.52);
              final detail = _segment(value, 0.30, 0.62);
              final exit = 1 - _segment(value, 0.78, 1.0);

              return Opacity(
                opacity: exit,
                child: ColoredBox(
                  color: BrandColors.navy,
                  child: SafeArea(
                    child: Center(
                      child: Semantics(
                        label:
                            'Bezpieczna Polska. Cywilne informacje o bezpieczeństwie.',
                        container: true,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Opacity(
                                opacity: enter,
                                child: Transform.translate(
                                  offset: Offset(
                                    0,
                                    reduceMotion ? 0 : 16 * (1 - enter),
                                  ),
                                  child: Transform.scale(
                                    scale: reduceMotion
                                        ? 1
                                        : 0.88 + (0.12 * enter),
                                    child: const BrandMark(size: 112),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              Opacity(
                                opacity: copy,
                                child: Transform.translate(
                                  offset: Offset(
                                    0,
                                    reduceMotion ? 0 : 10 * (1 - copy),
                                  ),
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
                              ),
                              const SizedBox(height: 12),
                              Opacity(
                                opacity: detail,
                                child: Container(
                                  width: 52,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: BrandColors.polishRed,
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Opacity(
                                opacity: detail,
                                child: const Text(
                                  'Cywilne informacje o bezpieczeństwie',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: BrandColors.mist,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.15,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
