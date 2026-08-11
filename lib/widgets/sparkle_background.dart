// widgets/sparkle_background.dart
//
// 2026-08-18: "I like the magic stars background indicating an
// actionable bit for the enduser. If this can be added somehow to all
// enduser actions, great." - was a private painter inside
// linking_screen.dart's checklist rows; extracted here so every
// interactive control in the app (checklist action rows, gif swipe
// confirms, the pull/push gesture zone, the pairing screen's drag
// target) can share the same twinkling-star hint instead of each
// screen growing its own copy. Widened to more sparkles across the
// full width - "too small, needed to be more on the left and right
// sides" - so it reads clearly even behind a full-width control, not
// just a small confirm button.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

/// Drop this behind actionable content (inside a Stack, sized to fill
/// via Positioned.fill) to hint "this is something you interact with".
class SparkleBackground extends StatefulWidget {
  const SparkleBackground({super.key});

  @override
  State<SparkleBackground> createState() => _SparkleBackgroundState();
}

class _SparkleBackgroundState extends State<SparkleBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(painter: _SparklePainter(_ctrl.value)),
    );
  }
}

class _SparklePainter extends CustomPainter {
  final double progress; // 0..1, loops
  _SparklePainter(this.progress);

  static const _positions = [
    Offset(0.03, 0.30), Offset(0.08, 0.70), Offset(0.16, 0.15),
    Offset(0.24, 0.55), Offset(0.34, 0.80), Offset(0.44, 0.25),
    Offset(0.56, 0.75), Offset(0.66, 0.20), Offset(0.76, 0.60),
    Offset(0.84, 0.15), Offset(0.92, 0.65), Offset(0.97, 0.30),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < _positions.length; i++) {
      final phase = (progress + i / _positions.length) % 1.0;
      final opacity = (math.sin(phase * math.pi * 2) * 0.5 + 0.5);
      final radius = 2.5 + opacity * 2.5;
      final center = Offset(
          _positions[i].dx * size.width, _positions[i].dy * size.height);
      final paint = Paint()
        ..color = kGreen.withOpacity(opacity * 0.6)
        ..strokeWidth = 1.4;
      canvas.drawLine(
          center.translate(-radius, 0), center.translate(radius, 0), paint);
      canvas.drawLine(
          center.translate(0, -radius), center.translate(0, radius), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklePainter old) =>
      old.progress != progress;
}
