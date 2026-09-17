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
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'action_gif.dart';
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
    // 2026-09-18: real feedback, live - "start and stop is immediate,
    // but needs to smoothly come to a start and stop." _playing used
    // to gate the painted t value directly - the whole particle layer
    // popped in and out in a single frame instead of easing in/out.
    // AnimatedOpacity cross-fades the layer itself, independent of the
    // particle animation underneath.
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: AnimatedOpacity(
        opacity: _playing ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
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
      ),
    );
  }
}

// 2026-09-17: real feedback, live - "Flow graphics removed the gifs,
// but should be behind it." The first version replaced git_push.gif/
// git_pull.gif with the flow animation outright - wanted both, flow
// as a background layer, the real gif still in front on top of it.
// Owns two separate keys internally (one per layer) and drives both
// through one shared TriggerableAnimation contract, so GifSwipeTrigger
// still only ever needs to know about one thing in its gif slot.
class FlowBehindGif extends StatefulWidget {
  final String assetPath;
  final bool isPush;
  final Color flowColor;
  final double height;
  const FlowBehindGif({
    super.key,
    required this.assetPath,
    required this.isPush,
    required this.flowColor,
    required this.height,
  });

  @override
  State<FlowBehindGif> createState() => _FlowBehindGifState();
}

class _FlowBehindGifState extends State<FlowBehindGif>
    implements TriggerableAnimation {
  final _flowKey = GlobalKey<FlowingDataAnimationState>();
  final _gifKey = GlobalKey<ActionGifState>();

  @override
  bool get isPlaying => _gifKey.currentState?.isPlaying ?? false;

  @override
  Future<void> trigger(Future<void> Function() action) async {
    // 2026-09-18: real crash, live - "I ran push and the app closed."
    // Both FlowingDataAnimationState.trigger and ActionGifState.trigger
    // call the function they're handed internally - passing the real
    // [action] (provider.pushRepository/pullRepository) to BOTH ran it
    // TWICE, concurrently, against the same repo's git2dart FFI layer.
    // That's a real double-push, not just a visual glitch - concurrent
    // native git access is exactly the kind of thing that brings the
    // whole app down instead of throwing a catchable Dart exception.
    //
    // Fix: [action] runs exactly once, here. Both animations are handed
    // a stand-in that just awaits a shared Completer, so each still
    // plays for its own 2000ms floor and still only finishes once the
    // real action does - without either one ever calling it directly.
    final completer = Completer<void>();
    final flowFuture = _flowKey.currentState?.trigger(() => completer.future);
    final gifFuture = _gifKey.currentState?.trigger(() => completer.future);
    try {
      await action();
    } finally {
      completer.complete();
    }
    await Future.wait([
      if (flowFuture != null) flowFuture,
      if (gifFuture != null) gifFuture,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          FlowingDataAnimation(
            key: _flowKey,
            isPush: widget.isPush,
            color: widget.flowColor,
            height: widget.height,
          ),
          ActionGif(
            key: _gifKey,
            assetPath: widget.assetPath,
            height: widget.height,
          ),
        ],
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
    // 2026-09-17: real feedback, live - "should be more direction top
    // right and bottom left." Was 0.85/-0.53 (mostly sideways, only a
    // little vertical) - now a true 45-degree corner-to-corner
    // diagonal, reads unambiguously as "toward that corner" instead of
    // "mostly sideways."
    final dx = isPush ? 0.78 : -0.78;
    final dy = isPush ? -0.78 : 0.78;
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
