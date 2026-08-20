// widgets/pulsing_glow.dart
//
// Soft green glow wrapper - the shared "it's live" cue used by the
// pairing screen's lock (key seated / pairing running) and the linking
// screen's vault drop target (something is being dragged over it).

import 'package:flutter/material.dart';
import '../theme.dart';

class PulsingGlow extends StatefulWidget {
  final bool active;
  final Widget child;
  // Fixed pixel glow size doesn't scale with what it wraps - the same
  // 24/4 default reads as strong around a small icon (vault drop target)
  // but weak around the much bigger pairing lock image (260x250). Callers
  // wrapping something large should pass bigger values to match visual
  // weight, rather than the glow just looking proportionally fainter.
  final double blurRadius;
  final double spreadRadius;
  // The glow follows this box's own shape, not the child's internal
  // drawing - a plain rectangle (default) casts a square-cornered glow
  // regardless of blur/spread size, even if the SVG inside has rounded
  // corners. Round this to match, or the glow just looks like a bigger
  // square instead of a proper halo.
  final double cornerRadius;
  const PulsingGlow({
    super.key,
    required this.active,
    required this.child,
    this.blurRadius = 24,
    this.spreadRadius = 4,
    this.cornerRadius = 0,
  });

  @override
  State<PulsingGlow> createState() => _PulsingGlowState();
}

class _PulsingGlowState extends State<PulsingGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: widget.cornerRadius > 0
              ? BorderRadius.circular(widget.cornerRadius)
              : null,
          boxShadow: [
            BoxShadow(
              color: kGreen.withValues(alpha: 0.15 + 0.15 * _ctrl.value),
              blurRadius: widget.blurRadius,
              spreadRadius: widget.spreadRadius,
            ),
          ],
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}
