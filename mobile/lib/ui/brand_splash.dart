import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'brand.dart';

class BrandStartupCover extends StatefulWidget {
  final Widget? child;
  final bool ready;

  const BrandStartupCover({
    super.key,
    required this.child,
    required this.ready,
  });

  @override
  State<BrandStartupCover> createState() => _BrandStartupCoverState();
}

class _BrandStartupCoverState extends State<BrandStartupCover> {
  Timer? _introTimer, _deadline;
  bool _introFinished = false, _deadlineReached = false;
  bool _fading = false, _visible = true;

  @override
  void initState() {
    super.initState();
    _introTimer = Timer(const Duration(milliseconds: 650), () {
      _introFinished = true;
      _dismissIfReady();
    });
    _deadline = Timer(const Duration(milliseconds: 2600), () {
      _deadlineReached = true;
      _dismissIfReady();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dismissIfReady();
  }

  @override
  void didUpdateWidget(covariant BrandStartupCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    _dismissIfReady();
  }

  void _dismissIfReady() {
    if (_fading || !_visible || widget.child == null) return;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (!_deadlineReached &&
        !(widget.ready && (_introFinished || reduceMotion))) {
      return;
    }
    _introTimer?.cancel();
    _deadline?.cancel();
    setState(() {
      _fading = true;
      if (reduceMotion) _visible = false;
    });
  }

  @override
  void dispose() {
    _introTimer?.cancel();
    _deadline?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.topLeft,
    fit: StackFit.expand,
    children: [
      IgnorePointer(
        ignoring: _visible,
        child: ExcludeSemantics(
          excluding: _visible,
          child: widget.child ?? const SizedBox.shrink(),
        ),
      ),
      if (_visible)
        AnimatedOpacity(
          opacity: _fading ? 0 : 1,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          onEnd: () {
            if (_fading) setState(() => _visible = false);
          },
          child: const BrandLoadingScreen(),
        ),
    ],
  );
}

class BrandLoadingScreen extends StatelessWidget {
  const BrandLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.15),
              radius: 0.78,
              colors: [BrandColors.navy, BrandColors.logoBackground],
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = math.min(
                    math.min(constraints.maxWidth * 0.72, 270.0),
                    constraints.maxHeight * 0.54,
                  );
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: reduceMotion ? 1 : 0, end: 1),
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.easeOutCubic,
                          builder: (context, progress, child) => Opacity(
                            opacity: 0.55 + progress * 0.45,
                            child: Transform.scale(
                              scale: 0.93 + progress * 0.07,
                              child: child,
                            ),
                          ),
                          child: BrandMark(
                            size: size,
                            semanticLabel: 'Logo Bezpieczna Polska',
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: 80,
                          child: ExcludeSemantics(
                            child: LinearProgressIndicator(
                              value: reduceMotion ? 1 : null,
                              minHeight: 2,
                              color: BrandColors.polishRed,
                              backgroundColor: const Color(0x40FFFFFF),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Ładowanie aplikacji…',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: BrandColors.mist,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.25,
                          ),
                        ),
                      ],
                    ),
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
