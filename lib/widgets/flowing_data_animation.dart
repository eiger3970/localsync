// widgets/flowing_data_animation.dart
//
// 2026-09-17: real ask, live - "Push pull flow, maybe on home screen
// when pushing or pulling?" Approved earlier as a standalone Python
// test (particles drifting NE for push, SW for pull, matching the
// direction language already used in help_wizard.dart's workflow
// icons) - this is the real Flutter version, wired into GifSwipeTrigger
// as a genuine alternative to a baked GIF for that exact slot. Same
// zero-asset-weight, theme-recolors-automatically reasoning as
// ExplodingLetter/FloatingHearts.
//
// Matches ActionGif's own timing contract (widgets/action_gif.dart) on
// purpose - GifSwipeTrigger drives whichever widget sits in its GIF
// slot through trigger()/isPlaying, so this needs to honor the exact
// same shape (2000ms floor, idle-shows-still-frame, token-based reset
// safety) to be a real drop-in, not a lookalike with different timing.
import 'dart:math';
import 'package:flutter/material.dart';
import 'triggerable_animation.dart';

class FlowingDataAnimation extends StatefulWidget {
  /// true = push (flows north-east, matches the app's established
  /// "sending out" direction language), false = pull (south-west).
  final bool isPush;
  final Color color;
  final double height;
  const FlowingDataAnimation({
    super.key,
    required this.isPush,
    required this.color,
    required this.height,
  });

  @override
  State<FlowingDataAnimation> createState() => FlowingDataAnimationState();
}

class FlowingDataAnimationState extends State<FlowingDataAnimation>
    with SingleTickerProviderStateMixin
    implements TriggerableAnimation {
  static const _minRun = Duration(milliseconds: 2000);
  late final AnimationController _ctrl;
  late final List<_Particle> _particles;
  bool _playing = false;
  int _runToken = 0;

  @override
  bool get isPlaying => _playing;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    final rng = Random(widget.isPush ? 11 : 17);
    _particles = List.generate(
      22,
      (_) => _Particle(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        startOffset: rng.nextDouble(),
        speed: 0.7 + rng.nextDouble() * 0.6,
        size: 2 + rng.nextDouble() * 3,
      ),
    );
  }

  @override
  Future<void> trigger(Future<void> Function() action) async {
    if (_playing) return;
    final token = ++_runToken;
    setState(() => _playing = true);
    _ctrl.repeat();
    await Future.wait([Future.delayed(_minRun), action()]);
    if (mounted && token == _runToken) {
      setState(() => _playing = false);
      _ctrl.stop();
    }
  }

  /// Plays for exactly the 2000ms floor, then calls [after] - matches
  /// ActionGifState.playThenRun's contract, unused by GifSwipeTrigger
  /// today but kept for parity in case a future caller needs it.
  Future<void> playThenRun(VoidCallback after) async {
    if (_playing) return;
    final token = ++_runToken;
    setState(() => _playing = true);
    _ctrl.repeat();
    await Future.delayed(_minRun);
    if (mounted && token == _runToken) {
      setState(() => _playing = false);
      _ctrl.stop();
      after();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => CustomPaint(
          painter: _FlowPainter(
            t: _playing ? _ctrl.value : 0,
            particles: _particles,
            color: widget.color,
            isPush: widget.isPush,
          ),
        ),
      ),
    );
  }
}

class _Particle {
  final double x, y, startOffset, speed, size;
  _Particle({
    required this.x,
    required this.y,
    required this.startOffset,
    required this.speed,
    required this.size,
  });
}

class _FlowPainter extends CustomPainter {
  final double t;
  final List<_Particle> particles;
  final Color color;
  final bool isPush;
  _FlowPainter({
    required this.t,
    required this.particles,
    required this.color,
    required this.isPush,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Push flows toward top-right, pull toward bottom-left - same
    // direction language as the north_east_rounded/south_west_rounded
    // arrows already used throughout this app (help_wizard.dart).
    final dx = isPush ? 0.85 : -0.85;
    final dy = isPush ? -0.53 : 0.53;
    final paint = Paint()..color = color;
    for (final p in particles) {
      final localT = (t * p.speed + p.startOffset) % 1.0;
      final x = ((p.x + dx * localT) % 1.2 - 0.1).clamp(-0.1, 1.1) * size.width;
      final y = ((p.y + dy * localT) % 1.2 - 0.1).clamp(-0.1, 1.1) * size.height;
      final fadeIn = localT < 0.15 ? localT / 0.15 : 1.0;
      final fadeOut = localT > 0.8 ? (1 - localT) / 0.2 : 1.0;
      final opacity = (fadeIn * fadeOut).clamp(0.0, 1.0) * 0.7;
      if (opacity <= 0.02) continue;
      canvas.drawCircle(
          Offset(x, y), p.size, paint..color = color.withValues(alpha: opacity));
    }
  }

  @override
  bool shouldRepaint(covariant _FlowPainter old) => old.t != t;
}
