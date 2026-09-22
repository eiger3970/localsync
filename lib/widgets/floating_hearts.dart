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

// 2026-09-22: module-level, outlives any single FloatingHearts instance
// - see _FloatingHeartsState's own 2026-09-22 comment for why tilt
// needs to survive a dialog close/reopen instead of resetting.
double _lastTilt = 0;
double _lastLean = 0;

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

class _FloatingHeartsState extends State<FloatingHearts>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_Heart> _hearts;
  // -1 (leaning left) .. 1 (leaning right), 0 at rest. Drives every
  // heart's sway together, on top of each one's own ambient drift -
  // see build()'s own 2026-09-18 comment for why this replaced touch,
  // and this field's own round-2 comment below for why it's gyroscope-
  // driven rather than accelerometer-driven.
  //
  // 2026-09-22: real feedback, live - "hearts should continue up from
  // last point of tilt, rather than auto sliding to the left text
  // edge." Every dialog open builds a brand-new _FloatingHeartsState -
  // starting `_tilt`/`_lean` at 0 every time meant a real tilt from a
  // PRIOR open was always forgotten, and the very next open looked like
  // an unwanted slide back to the idle/ambient position near SUPPORT.
  // Seeded from the module-level `_lastTilt`/`_lastLean` below instead
  // (same "persist across widget instances" pattern this codebase
  // already uses for _pullKey/_pushKey/_quickActionScheduled in
  // home_screen.dart) - a fresh open now continues exactly where the
  // last one left off, not just the same TARGET but the same already-
  // eased visual position too, so there's no re-glide-from-center
  // transient on reopen either.
  double _tilt = _lastTilt;
  // 2026-09-22: the continuous, eased value the painter actually reads
  // - see this file's own top-of-file 2026-09-22 comment. Glides
  // toward `_tilt` every frame in build()'s AnimatedBuilder callback
  // rather than jumping straight to it.
  double _lean = _lastLean;
  DateTime? _lastFrameTime;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  // 2026-09-22 (round 2): real feedback, live, UNCHANGED after the
  // dialog-reopen persistence fix above - "hearts incorrectly slide to
  // the left text edge" when the phone isn't deliberately being turned
  // right. Since the persistence fix didn't touch this, the real cause
  // was never dialog reopen at all - it's this: a SINGLE gyroscope
  // sample over 0.5 rad/s is enough to latch a direction, and ordinary
  // handling (adjusting grip, scrolling this same dialog with a thumb)
  // can easily produce one brief spike that fast without the user
  // perceiving it as "tilting" at all. These two fields require the
  // SAME direction to hold for a real, sustained stretch (not one
  // sample) before actually committing to it - see the listener below.
  double? _turnCandidateSign;
  DateTime? _turnCandidateStart;

  @override
  void initState() {
    super.initState();
    // 2026-09-18 (round 2): real feedback, live - "I tilt the phone top
    // end right and nothing, then tilt phone top end left and nothing."
    // The accelerometer version (round 1) only reacted to actual TILT
    // ANGLE - rolling the device like tipping a tray. "Top end
    // right/left" while holding the phone upright to read it is a YAW
    // turn (swinging the top around, like turning a steering wheel) -
    // that doesn't change gravity's direction relative to the device at
    // all, so the accelerometer genuinely never saw it. Gyroscope's z
    // axis (angular velocity around the screen-normal axis) is what
    // actually detects this motion.
    //
    // Accumulated into _tilt rather than read directly - gyroscope
    // reports rotation SPEED, not a resting angle, so a phone held
    // still (even mid-turn, even tilted) reports ~0; reading it
    // directly would snap the sway back to center the instant the turn
    // stopped. Accumulating instead means it holds wherever you leave
    // it (round 4 below removed the original decay-back-to-center
    // entirely) - matches "collect on the edge and continue floating
    // up" (stays leaned) rather than springing back instantly.
    //
    // 2026-09-18 (round 3): real feedback, live - "unsure is swaying or
    // not, but the movement if any is too small." 0.12 -> 0.4 - a
    // normal, unhurried turn should reach full sway well before the
    // motion finishes, not need an exaggerated snap-turn to register at
    // all. Paired with the painter's own edge-snap change (blends all
    // the way to the true edge at full tilt, not a fixed small offset).
    //
    // 2026-09-18 (round 4): real feedback, live - "Hearts seems to
    // move, but I can't make sense of it. They should be steerable like
    // something to play with and move the phone around." The decay
    // (below, since removed) fought against holding a position -
    // turning the phone to a spot and holding it still there still let
    // the lean drift back toward center on its own, which doesn't read
    // as "steerable." No decay now - _tilt holds exactly where you
    // leave it, like a real steering wheel: turn one way and it stays
    // that way until you physically turn it back the other way
    // yourself, not on a timer.
    // 2026-09-18 (round 9): real bug, found by reasoning through why
    // "n increases" (events genuinely firing) but hearts still never
    // moved left/right. Removing decay (round 4) meant nothing was ever
    // pulling _tilt back toward 0 - ordinary gyroscope sensor noise
    // (small non-zero readings even while the phone sits still) keeps
    // accumulating in whatever direction it happens to drift, and with
    // no decay to counter it, _tilt inevitably saturates at -1 or 1
    // from noise alone within a few seconds, regardless of how the
    // phone is actually being turned afterward - it just looks stuck.
    // A deadzone fixes this at the source instead of reintroducing
    // decay (which was removed for a real reason - it fought against
    // holding a deliberate position): readings below real turning speed
    // are ignored entirely, so noise never contributes at all, while a
    // genuine turn (much faster than sensor noise) still accumulates
    // and holds exactly as before.
    //
    // 2026-09-18 (round 12): real bug, confirmed by the round-11
    // diagnostic - "GYRO shows green background" STAYING green (not
    // flickering) with hearts still showing no reaction. That pins it:
    // the accumulator was never actually broken, it was PERMANENTLY
    // SATURATED. Ordinary handling (picking the phone up, holding it to
    // read the screen) easily exceeds 0.03 rad/s - far below deliberate
    // turning speed - so _tilt drifted to +-1 within seconds of the
    // dialog opening, every time, before any real "steering" input even
    // happened. With zero decay (round 4), once saturated it can never
    // recover on its own, so it just looks permanently frozen at one
    // edge and further tilting has nowhere left to go.
    //
    // Replaced the leaky integral with a direct latch: a real, fast
    // turn (0.5 rad/s - well above incidental handling, but a normal
    // deliberate wrist-turn clears it easily) sets the lean outright;
    // anything slower is ignored and leaves the lean exactly where it
    // was. No accumulation at all, so there is nothing left to
    // saturate - it can only ever be -1, 0, or 1, and only changes on a
    // real turn.
    // 2026-09-22: real bug, live - "hearts slide opposite way to
    // gravity, should slide right with right phone tilt." Sign was
    // inverted. The device's z axis points OUT of the screen toward the
    // user, so by the right-hand rule a POSITIVE angular velocity
    // around it is counterclockwise as the user looks at the screen -
    // i.e. the phone's top swinging LEFT, not right. Turning the top
    // right is clockwise from the user's viewpoint, which is NEGATIVE
    // z. The mapping below had this backwards (positive z -> +1 ->
    // right edge); flipped so positive z (top swinging left) now maps
    // to -1 (left edge), matching this field's own documented meaning.
    // 2026-09-22 (round 2): real feedback, live, still happening after
    // round 1's persistence fix - "hearts incorrectly slide to the left
    // text edge" from ordinary handling, not a deliberate turn. A single
    // sample above turnThreshold used to commit instantly; now the SAME
    // direction has to hold for `sustainedTurnDuration` before it
    // actually latches, so a brief incidental spike (one frame of grip
    // adjustment) gets reset by the very next normal-speed sample
    // instead of committing - a real, deliberate wrist-turn easily
    // holds direction for longer than 120ms, so this doesn't cost any
    // real responsiveness.
    const turnThreshold = 0.5;
    const sustainedTurnDuration = Duration(milliseconds: 120);
    _gyroSub = gyroscopeEventStream().listen((event) {
      if (!mounted) return;
      if (event.z.abs() < turnThreshold) {
        _turnCandidateSign = null;
        return;
      }
      final sign = event.z > 0 ? -1.0 : 1.0;
      final now = DateTime.now();
      if (_turnCandidateSign != sign) {
        _turnCandidateSign = sign;
        _turnCandidateStart = now;
        return;
      }
      if (now.difference(_turnCandidateStart!) >= sustainedTurnDuration) {
        _tilt = sign;
        _lastTilt = _tilt;
      }
    }, onError: (_) {
      // Motion access denied/unavailable on this device/signing setup -
      // hearts just keep their ambient sway with no tilt reaction,
      // nothing left to update.
    });
    // 2026-09-18: real feedback, live - "too slow rising up." Was 9s
    // for a full cycle even at the old, much shorter 90px trail - with
    // the trail now 420px tall (reaching the dialog's top, see the
    // call site's own 2026-09-18 comment) the same 9s would have read
    // as far slower still. 5s base plus a faster speed range keeps the
    // rise reading as a brisk trickle, not a crawl, across the taller
    // distance.
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
    final rng = Random(3);
    // 2026-09-17: "a trail with random spacing" - startOffset staggers
    // each heart's own cycle so they never move in lockstep, reading
    // as an irregular trickle rather than a synchronized pulse.
    _hearts = List.generate(
      widget.quiet ? 3 : 5,
      (_) => _Heart(
        x: 0.5 + (rng.nextDouble() - 0.5) * 0.5,
        startOffset: rng.nextDouble(),
        speed: 0.6 + rng.nextDouble() * 0.5,
        size: 7 + rng.nextDouble() * 6,
        // 2026-09-18 (round 14): real bug, found by reasoning after the
        // on-canvas stripe (round 13) proved tilt genuinely reaches this
        // painter, correctly, every time - "same no movement left/right"
        // even so. The tilt-snap logic itself was never broken: h.x
        // (0.25-0.75) plus the OLD drift range here (+-0.3) already put
        // hearts within reach of both true edges as part of ordinary
        // ambient sway, with nothing tilt-specific to distinguish it
        // from a hard edge-snap - the reaction was real but invisible
        // against its own idle motion. 0.6 -> 0.15 keeps ambient sway
        // clearly centered, so a tilt-snap to the true edge is now an
        // unmistakable jump instead of "maybe a bit further than usual."
        drift: (rng.nextDouble() - 0.5) * 0.15,
        driftPhase: rng.nextDouble() * 2 * pi,
      ),
    );
  }

  @override
  void dispose() {
    _gyroSub?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 2026-09-18: no gesture detection at all any more (was: touch-drag,
    // then Listener-based raw pointer tracking, through several rounds
    // that still didn't read as working on a real device) - see this
    // file's own top-of-file comment for why tilt replaced touch
    // entirely instead of another round of gesture tuning.
    return SizedBox(
      width: widget.trailWidth,
      height: widget.trailHeight,
      child: AnimatedBuilder(
        animation: _ctrl,
        // 2026-09-22: eases `_lean` toward the latched `_tilt` target
        // every tick (real elapsed time, not a fixed per-frame step, so
        // the glide speed doesn't depend on the device's refresh rate)
        // instead of handing the painter the raw instantly-latched
        // value - see this file's own top-of-file comment.
        builder: (_, __) {
          final now = DateTime.now();
          final dt = _lastFrameTime == null
              ? 0.0
              : now.difference(_lastFrameTime!).inMicroseconds / 1e6;
          _lastFrameTime = now;
          // 2026-09-22: real feedback, live - "hearts jump quickly...
          // can hearts slide slower." 4.0 reached the edge in ~1s (fast
          // enough to still read as a jump) - 1.2 stretches the same
          // glide to ~3s, now a real visible motion.
          const easeRate = 1.2; // higher = snappier glide
          final alpha = 1 - exp(-easeRate * dt);
          _lean += (_tilt - _lean) * alpha;
          // 2026-09-22: real ask, live - "hearts need to slide until
          // reaching the left or right edge." Pure exponential easing
          // only ever approaches _tilt asymptotically, never quite
          // landing on it - close enough to look "arrived" after ~1s,
          // but the painter's own edge blend (leanAbs, see
          // _HeartsPainter.paint) would technically never hit the exact
          // true edge pixel. Snap once the gap is imperceptible so it
          // actually, exactly arrives.
          if ((_tilt - _lean).abs() < 0.01) _lean = _tilt;
          _lastLean = _lean;
          return CustomPaint(
            painter: _HeartsPainter(
                t: _ctrl.value,
                hearts: _hearts,
                color: widget.color,
                quiet: widget.quiet,
                tilt: _lean),
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
  // 2026-09-18: real ask, live - "swaying phone sideways left or right"
  // (see floating_hearts.dart's own top-of-file comment for why this
  // replaced touch) - -1 (tilted left) .. 1 (tilted right), 0 at rest.
  final double tilt;
  _HeartsPainter(
      {required this.t,
      required this.hearts,
      required this.color,
      this.quiet = false,
      this.tilt = 0});

  @override
  void paint(Canvas canvas, Size size) {
    // 2026-09-18 (round 13): confirmed by real feedback, live - "Hearts
    // show funny stripe." The debug rect that used to live here (a
    // bright bar filling this exact box whenever tilt was active) did
    // its job: it proved tilt genuinely reaches this canvas, in the
    // right place, at the right time - and was very likely obscuring
    // the actual hearts underneath it while it was up. Removed now that
    // the question it existed to answer is settled.
    for (final h in hearts) {
      final localT = (t * h.speed + h.startOffset) % 1.0;
      // y=size.height (the widget's own bottom edge, right at SUPPORT's
      // row) at localT=0, rising to y=0 (top of this widget's box,
      // above the row) at localT=1 - a real, local trail, not a
      // fraction of some distant ancestor's height.
      final y = size.height * (1 - localT);
      final sway = sin(localT * 2 * pi + h.driftPhase) * h.drift;
      // 2026-09-22: real feedback, live - "hearts jump quickly from
      // left text edge to middle... can hearts slide slower to left and
      // right phone edges?" Two distinct things folded into one ask:
      // (1) the box itself now spans much closer to the real screen
      // edges (see the call site's own comment for the width), so the
      // tilt-glide has somewhere real to go - but (2) the IDLE ambient
      // sway must stay anchored near SUPPORT's icon (the 2026-09-17
      // "stem from support" requirement, still in force) rather than
      // stretching out across the whole new width too. `_restWidth`
      // keeps the ambient anchor at the same real on-screen distance
      // from SUPPORT as before the box widened - only the tilt-glide
      // target below (`edgeX`, using the real `size.width`) reaches the
      // new true edge.
      final baseX =
          (_restWidth * (h.x + sway)).clamp(0.0, size.width);
      final leanAbs = tilt.abs();
      final edgeX = tilt > 0 ? size.width : 0.0;
      final x = _lerp(baseX, edgeX, leanAbs);
      // Fade in near the bottom (origin), fade out near the top - never
      // pops in/out abruptly mid-rise.
      final fadeIn = localT < 0.15 ? localT / 0.15 : 1.0;
      final fadeOut = localT > 0.78 ? (1 - localT) / 0.22 : 1.0;
      final ambientOpacity =
          (fadeIn * fadeOut).clamp(0.0, 1.0) * (quiet ? 0.3 : 0.5);
      final opacity = _lerp(ambientOpacity, 1.0, leanAbs);
      if (opacity <= 0.02) continue;
      final glyphSize = _lerp(h.size, h.size * 1.8, leanAbs);
      _paintHeartGlyph(
          canvas, Offset(x, y), glyphSize, color.withValues(alpha: opacity));
    }
  }

  // 2026-09-22: the original, deliberately narrow column width hearts
  // idle within near SUPPORT - unrelated to `trailWidth` now, which is
  // the much wider real box the tilt-glide travels across. See this
  // method's own call-site comment above.
  static const _restWidth = 140.0;

  static double _lerp(double a, double b, double t) =>
      a + (b - a) * t.clamp(0.0, 1.0);

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
  bool shouldRepaint(covariant _HeartsPainter old) => old.t != t;
}
