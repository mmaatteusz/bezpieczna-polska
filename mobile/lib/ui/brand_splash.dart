import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'brand.dart';

class BrandSplashGate extends StatefulWidget {
  final Widget child;
  final ValueListenable<bool> ready;

  const BrandSplashGate({
    super.key,
    required this.child,
    required this.ready,
  });

  @override
  State<BrandSplashGate> createState() => _BrandSplashGateState();
}

class _BrandSplashGateState extends State<BrandSplashGate>
    with SingleTickerProviderStateMixin {
  static const _minimumDuration = Duration(milliseconds: 1350);
  static const _maximumDuration = Duration(milliseconds: 4500);

  late final AnimationController _controller;
  Timer? _minimumTimer;
  Timer? _maximumTimer;
  bool _minimumElapsed = false;
  bool _showSplash = true;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _controller.animateTo(
      0.90,
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeOutCubic,
    );
    widget.ready.addListener(_tryFinish);

    _minimumTimer = Timer(_minimumDuration, () {
      _minimumElapsed = true;
      _tryFinish();
    });
    _maximumTimer = Timer(_maximumDuration, () {
      unawaited(_finish());
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _tryFinish());
  }

  @override
  void didUpdateWidget(covariant BrandSplashGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ready == widget.ready) return;
    oldWidget.ready.removeListener(_tryFinish);
    widget.ready.addListener(_tryFinish);
    _tryFinish();
  }

  @override
  void dispose() {
    widget.ready.removeListener(_tryFinish);
    _minimumTimer?.cancel();
    _maximumTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _tryFinish() {
    if (!_showSplash || _finishing || !_minimumElapsed) return;
    if (widget.ready.value) unawaited(_finish());
  }

  Future<void> _finish() async {
    if (!_showSplash || _finishing) return;
    _finishing = true;
    _maximumTimer?.cancel();
    await _controller.animateTo(
      1,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
    if (mounted) setState(() => _showSplash = false);
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

    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(child: widget.child),
        AbsorbPointer(
          child: ColoredBox(
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
                            MediaQuery.maybeOf(context)?.disableAnimations ??
                            false;
                        final enter = _segment(value, 0.02, 0.28);
                        final copy = _segment(value, 0.10, 0.36);
                        final detail = _segment(value, 0.18, 0.46);

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
                                  scale: reduceMotion
                                      ? 1
                                      : 0.90 + (0.10 * enter),
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
                                    value: value,
                                    minHeight: 5,
                                    backgroundColor: BrandColors.navySoft,
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
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
          ),
        ),
      ],
    );
  }
}
