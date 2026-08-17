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
  const PulsingGlow({super.key, required this.active, required this.child});

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
          boxShadow: [
            BoxShadow(
              color: kGreen.withOpacity(0.15 + 0.15 * _ctrl.value),
              blurRadius: 24,
              spreadRadius: 4,
            ),
          ],
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}
