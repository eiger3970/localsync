// widgets/floating_hearts.dart
//
// 2026-09-17: real ask, live - "SUPPORT, loves hearts pour out
// randomly over screen, floating like bubbles at least to top to
// catch attention of users at top that don't scroll down far." First
// version was a Stack overlay above the WHOLE dialog, rising from the
// fixed viewport's bottom to top regardless of scroll - deliberately
// NOT tied to SUPPORT's real position, to reach users who never
// scroll that far.
//
// 2026-09-17, corrected same day - real feedback, live: "hearts
// aren't coming from support they're just near the top. Need to stem
// from support, like a trail with random spacing, floating upwards."
// The compromise above wasn't close enough - this version genuinely
// stems from SUPPORT's real position: home_screen.dart now positions
// this directly above the SUPPORT row itself (inside the scrolling
// content, with Clip.none so it isn't clipped by its own immediate
// parent), rising a fixed distance above that fixed point. Trades
// away "visible to non-scrollers" for "actually looks like it's
// coming from the heart icon" - the user's own repeated, increasingly
// specific asks made clear which one mattered more.
//
// Pure CustomPainter, no asset - same reasoning as exploding_letter.dart
// (real Flutter animation, zero file weight). Hearts are drawn by
// painting the real Icons.favorite glyph via TextPainter, not a hand-
// drawn path, so they match the app's own icon language exactly.
//
// 2026-09-18: real ask, live - "swaying phone sideways left or right,
// no touch complications with scrolling screen touching actions." Went
// through several rounds of touch-gesture fixes (radius, edge-snap,
// wider column) that still didn't read as working on-device - touch
// interaction competing with the ancestor scroll view for the same
// gesture was a fight no amount of tuning was going to fully win.
// Device tilt (gyroscope) replaces touch entirely here - no gesture, no
// scroll conflict, nothing to compete for at all.
//
// 2026-09-22: real feedback, live - "hearts don't sway left and right,
// rather jump and appear left and then appear right... looking for a
// smooth glide." The 2026-09-18 rounds above deliberately landed on a
// hard binary snap (round 8's own comment: "past a small threshold,
// every heart sits exactly on that edge, full stop") because the
// earlier proportional blend was too subtle to register as a reaction
// at all on-device. Now that the gyro plumbing itself is proven working
// (confirmed independently twice over, rounds 13/15), the ask has moved
// from "is it reacting" to "does it look natural" - the instant x-jump
// is now the actual problem, not too-subtle motion. Fixed by keeping
// the tilt LATCH as-is (still -1/0/1, still only changes on a real fast
// turn, see round 12's comment below) but no longer feeding it straight
// into the painter - _lean now eases toward that target every frame
// (real elapsed time, not frame-count, so it's consistent regardless of
// device refresh rate), and the painter blends each heart's x/size/
// opacity toward the edge proportionally to |_lean| instead of jumping.
// Same steering-wheel semantics as before (holds wherever tilted, only
// moves on a deliberate turn), now visibly gliding there instead of
// teleporting.
//
// Also removed the on-screen "GYRO n=.. tilt=.." debug overlay (round 5
// -14) - it did its job (proved the gyro stream and painter were both
// genuinely wired up, several rounds ago) and was explicitly flagged
// "remove once this is resolved" when added. Leaving real debug text
// and a colored rect visible to an actual user was never the intent.
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

// 2026-09-22 (round 7): real feedback, live - "if I jerk the phone
// right the hearts go right, but otherwise hearts gravitate to the
// left edge." Removed the module-level persistence this file used to
// have here (added round 1, "hearts should continue up from last
// point of tilt" on dialog reopen). That reasoning belonged to the OLD
// hold-forever tilt design (round 4, 2026-09-18) - round 3 (2026-09-22)
// explicitly replaced that with decay-to-center physics, but this
// leftover persistence never got reconciled with the new model, and
// under decay-to-center it can only cause harm: decay only runs while
// this widget is actually mounted (the AnimatedBuilder driving it is
// disposed the instant the dialog closes), so any session closed
// before decay fully finishes settling back to 0 freezes whatever
// residual lean it had at that exact moment - and the NEXT open
// inherited that stale value instead of genuinely starting at rest.
// Repeated open/close testing cycles could accumulate exactly this
// kind of "gravitates left for no reason" drift. Under the current
// physics, every fresh open should start at true center, full stop -
// there's no reason left to remember anything across instances.

class FloatingHearts extends StatefulWidget {
  final Color color;
  // How far above its own origin (y=0, bottom of this widget's box)
  // hearts rise before fading out.
  final double trailHeight;
  // 2026-09-17: fixed width, not double.infinity - this now lives in a
  // Positioned(left: 0, ...) with no matching `right`, which needs a
  // concrete width from its child rather than an unbounded one.
  //
  // 2026-09-18: real feedback, live - "Hearts no change, just the
  // screen scrolls. The hearts might need a generous space around them
  // for user fingers to drag." 70 -> 140 - a real fingertip is roughly
  // 40-50px, so 70 left very little room either side of a heart to
  // actually initiate a touch that lands inside this column at all.
  //
  // 2026-09-22: touch is long gone (tilt replaced it, see this file's
  // own top-of-file 2026-09-18 comment), so the "room to drag" reason
  // above is stale - real ask now, live: "hearts need to slide until
  // reaching the left or right phone edges." This is the real box the
  // tilt-glide travels across, so the call site now passes something
  // close to the dialog's actual content width, not a small fixed
  // number. The IDLE "stem from support" anchor stays narrow regardless
  // of this value - see _HeartsPainter's own `_restWidth`.
  final double trailWidth;
  // 2026-09-18: real ask, live - "Support floating hearts decrease per
  // higher tiers." Paying users already get a calmer app overall (no
  // ads, see FreeTierBannerAd's own gating) - fewer, fainter hearts is
  // the same idea applied here. Fewer hearts (3, not 5) and a lower
  // opacity ceiling, not a different animation - still the same trail.
  final bool quiet;
  const FloatingHearts({
    super.key,
    required this.color,
    this.trailHeight = 90,
    this.trailWidth = 140,
    this.quiet = false,
  });

  @override
  State<FloatingHearts> createState() => _FloatingHeartsState();
}

// 2026-09-24 (round 8): real feedback, live, launch check list - "Hearts
// in About unable to steer left and right, then float up rather than
// slide to the left edge." Two root causes, both in the gyroscope model
// rounds 1-7 kept tuning:
//  1. A gyroscope reports rotation SPEED, not angle - so _tilt was an
//     integral of noisy rates. Any small bias above the noise floor
//     added up between decays, which is the "gravitates to the left
//     edge" drift no sensitivity/decay tuning could fully remove.
//  2. The painter lerped every heart's x all the way to a wall by
//     |tilt| - so any lean at all read as hearts sliding sideways to an
//     edge as a block, not rising.
// Now: the steer angle comes from GRAVITY (accelerometer x), an
// absolute reading - upright is 0 by physics, no integral, nothing to
// drift. And steering bends each heart's upward path toward the tilted
// side, more the higher it has risen (like wind on a rising bubble) -
// hearts always keep floating up, and curve left/right with the phone.
class _FloatingHeartsState extends State<FloatingHearts>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_Heart> _hearts;
  // Target steer from the latest accelerometer sample, -1..1.
  double _steerTarget = 0;
  // Smoothed steer actually painted - eases toward _steerTarget per
  // frame (real elapsed time, so the glide is the same at 60 or 120Hz).
  double _steer = 0;
  DateTime? _lastFrameTime;
  StreamSubscription<AccelerometerEvent>? _accelSub;

  // Tilt angle (from upright) that counts as full steer: ~30 degrees,
  // a comfortable steering-wheel turn, not a phone held sideways.
  static const _fullSteerSin = 0.5;
  // Ignore anything under ~5 degrees - normal hand wobble.
  static const _deadZone = 0.08;
  // accelerometer x is positive or negative for a right-side-down tilt
  // depending on platform convention; flip this one sign if on-device
  // the hearts steer the opposite way to the turn.
  static const _steerSign = -1.0;

  @override
  void initState() {
    super.initState();
    _accelSub =
        accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval)
            .listen((event) {
      if (!mounted) return;
      final raw = (event.x / 9.81 / _fullSteerSin).clamp(-1.0, 1.0);
      _steerTarget =
          raw.abs() < _deadZone ? 0.0 : (_steerSign * raw).toDouble();
    }, onError: (_) {
      // No accelerometer (simulator, desktop preview) - hearts simply
      // rise straight, same as holding the phone upright.
    });
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
    final rng = Random(3);
    _hearts = List.generate(
      widget.quiet ? 3 : 5,
      (_) => _Heart(
        x: 0.5 + (rng.nextDouble() - 0.5) * 0.5,
        startOffset: rng.nextDouble(),
        speed: 0.6 + rng.nextDouble() * 0.5,
        size: 7 + rng.nextDouble() * 6,
        drift: (rng.nextDouble() - 0.5) * 0.15,
        driftPhase: rng.nextDouble() * 2 * pi,
      ),
    );
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.trailWidth,
      height: widget.trailHeight,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final now = DateTime.now();
          final dt = _lastFrameTime == null
              ? 0.0
              : now.difference(_lastFrameTime!).inMicroseconds / 1e6;
          _lastFrameTime = now;
          const easeRate = 3.0; // higher = snappier response to a turn
          _steer += (_steerTarget - _steer) * (1 - exp(-easeRate * dt));
          return CustomPaint(
            painter: _HeartsPainter(
                t: _ctrl.value,
                hearts: _hearts,
                color: widget.color,
                quiet: widget.quiet,
                steer: _steer),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _Heart {
  final double x; // 0..1, horizontal position within this widget's box
  final double startOffset; // 0..1, staggers each heart's cycle start
  final double speed; // relative rise speed multiplier
  final double size;
  final double drift; // horizontal sway amplitude
  final double driftPhase;
  _Heart({
    required this.x,
    required this.startOffset,
    required this.speed,
    required this.size,
    required this.drift,
    required this.driftPhase,
  });
}

class _HeartsPainter extends CustomPainter {
  final double t; // 0..1, loops
  final List<_Heart> hearts;
  final Color color;
  final bool quiet;
  final double steer; // -1 (left) .. 1 (right), smoothed
  _HeartsPainter(
      {required this.t,
      required this.hearts,
      required this.color,
      this.quiet = false,
      this.steer = 0});

  @override
  void paint(Canvas canvas, Size size) {
    for (final h in hearts) {
      final localT = (t * h.speed + h.startOffset) % 1.0;
      final y = size.height * (1 - localT);
      final sway = sin(localT * 2 * pi + h.driftPhase) * h.drift;
      final baseX = (_restWidth * (h.x + sway)).clamp(0.0, size.width);
      // Round 8: steering bends the rising path - the offset grows with
      // height (localT, eased), so a heart leaves SUPPORT where it
      // always does and curves toward the tilted side as it rises,
      // reaching up to the box edge near the top. Never a sideways slide
      // of the whole trail.
      final bend = steer * size.width * Curves.easeIn.transform(localT);
      final x = (baseX + bend).clamp(0.0, size.width);
      final fadeIn = localT < 0.15 ? localT / 0.15 : 1.0;
      final fadeOut = localT > 0.78 ? (1 - localT) / 0.22 : 1.0;
      final opacity =
          (fadeIn * fadeOut).clamp(0.0, 1.0) * (quiet ? 0.3 : 0.5);
      if (opacity <= 0.02) continue;
      _paintHeartGlyph(
          canvas, Offset(x, y), h.size, color.withValues(alpha: opacity));
    }
  }

  static const _restWidth = 140.0;

  void _paintHeartGlyph(Canvas canvas, Offset center, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.favorite.codePoint),
        style: TextStyle(
          fontSize: size,
          fontFamily: Icons.favorite.fontFamily,
          package: Icons.favorite.fontPackage,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _HeartsPainter old) =>
      old.t != t || old.steer != steer;
}
