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
  // 2026-09-22 (round 3): real feedback, live - "hearts should simply
  // follow physics: sway left or right until the phone is straight,
  // then momentum would gently continue upwards without left or right
  // sway." This directly overturns the "steering wheel, holds wherever
  // you leave it, never decays on its own" design decided in round 4
  // below (2026-09-18) - every "hearts stuck/auto-slid to an edge"
  // complaint since then (rounds 1 and 2 above included) was this same
  // design working exactly as built: once tilted, it was NEVER meant to
  // return to center on its own. The user's own restated intent makes
  // clear that was the wrong model all along, not a bug in it. Real
  // physics now: `_tilt` continuously integrates raw angular velocity
  // (sway grows the longer/faster the real turn) AND continuously
  // decays back toward 0 every frame (see build()'s own 2026-09-22
  // round-3 comment) - turning the phone sways it, releasing it (phone
  // back to level) lets it settle back to straight-up within about a
  // second, same as a pendulum losing momentum. The old latch/debounce
  // mechanism (turnThreshold snap, then a sustained-direction
  // requirement) is gone entirely, not tuned further - it was the wrong
  // shape of fix for a "should return to center" requirement no amount
  // of noise-filtering could ever satisfy.
  double _tilt = 0;
  // 2026-09-22: the continuous, eased value the painter actually reads
  // - see this file's own top-of-file 2026-09-22 comment. Glides
  // toward `_tilt` every frame in build()'s AnimatedBuilder callback
  // rather than jumping straight to it.
  double _lean = 0;
  DateTime? _lastFrameTime;
  // 2026-09-22 (round 5): real elapsed time between gyro samples, used
  // to make accumulation rate-independent - see the gyro listener's own
  // round-5 comment for why this is needed now.
  DateTime? _lastGyroSampleTime;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

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
    // Between 2026-09-18 and 2026-09-22 this went through many rounds
    // (accumulate-and-hold, deadzone, a hard latch, a sustained-turn
    // debounce) all built on the same premise decided in round 4
    // (2026-09-18): "_tilt holds exactly where you leave it, like a
    // real steering wheel... not on a timer." That premise is what the
    // 2026-09-22 round-3 comment above overturns - the user's own
    // restated intent is real decay-to-center physics, not a hold. None
    // of the intermediate designs are worth keeping detail on; they
    // were all tuning the wrong model. Full history in this file's own
    // git log if it's ever needed again.
    //
    // Direction: the device's z axis points OUT of the screen toward
    // the user, so by the right-hand rule a positive angular velocity
    // around it is counterclockwise as the user looks at the screen -
    // the phone's top swinging LEFT, not right - hence the negation
    // below (matches this field's own -1-left/+1-right convention).
    //
    // Real physics, decided 2026-09-22 (round 3): each gyro sample
    // nudges `_tilt` by an amount proportional to how fast the phone is
    // actually turning (a gentle wobble barely moves it, a real
    // deliberate turn reaches full lean in well under a second) -
    // small samples below `noiseFloor` are ignored so pure sensor noise
    // contributes nothing at all. Decay back toward 0 happens
    // separately, every frame, in build()'s own AnimatedBuilder
    // callback below - not here, since gyro events alone can't be
    // relied on to keep arriving once the phone is actually held still.
    //
    // 2026-09-22 (round 4): real regression, live - "hearts don't sway
    // with tilt now." Root cause confirmed directly from the installed
    // sensors_plus package source, not guessed: gyroscopeEventStream()
    // defaults to SensorInterval.normalInterval, which is a real 200ms
    // (5Hz) - genuinely sparse. Decay above runs every ANIMATION frame
    // (~16ms, ~60Hz) regardless of whether a gyro sample just arrived,
    // so between two default-rate samples, decay erodes roughly a fifth
    // of whatever the previous sample contributed before the next one
    // even lands - accumulation and decay were fighting on wildly
    // different clocks. gameInterval (20ms, ~50Hz) brings gyro sampling
    // close enough to the animation frame rate that decay no longer
    // outpaces it between samples.
    //
    // 2026-09-22 (round 5): real regression, live - "hearts auto flow
    // to left edge, rather than just up from where tilt ends." Real
    // math bug in round 4's own fix: accumulation was a flat
    // per-SAMPLE increment, with no time factor - switching from 5Hz to
    // 50Hz sampling meant the SAME real motion now contributes roughly
    // 10x more total accumulation per second than before (10x more
    // samples, each still adding the same fixed amount), against a
    // decay rate that was already correctly time-based and unchanged.
    // Ordinary motion could now consistently outrun decay toward
    // whichever direction it happened to lean. Real fix: scale each
    // sample's contribution by the REAL elapsed time since the
    // previous sample (matching how decay already works), so the total
    // accumulated lean only depends on the actual physical motion, not
    // how often it happens to get sampled.
    //
    // 2026-09-22 (round 6): real feedback, live, after round 5 - "hearts
    // are incorrectly small... auto flow to left edge, rather than just
    // up from where tilt ends" - SAME wording as round 5, meaning that
    // fix's math was right but its TUNING wasn't. Two real, distinct
    // sensor-behavior reasons, not one:
    // (1) Real deliberate turns almost certainly aren't reaching
    // anywhere near round 5's assumed 2 rad/s - size staying small
    // (glyphSize blends toward the same leanAbs the x-position does, see
    // _HeartsPainter.paint) means `_tilt` was never getting close to
    // full lean even during a real intentional tilt. Sensitivity raised
    // well past what 2 rad/s would need, so a realistic, more moderate
    // real turn still reaches full lean quickly.
    // (2) Consumer MEMS gyroscopes commonly have a small persistent
    // per-device z-axis BIAS (a fixed non-zero reading even when
    // genuinely still, not random noise that averages out) - if that
    // bias sits above the old 0.04 rad/s noise floor, it never gets
    // filtered out at all, and unlike real noise it doesn't cancel
    // itself over time: it just steadily pushes `_tilt` one direction,
    // settling wherever that steady push balances decay - never quite
    // 0, never a real drift so extreme it reads as "stuck," matching
    // "small" hearts that still won't go fully straight. Raised well
    // above plausible bias levels while staying far below genuine
    // deliberate-turn speed.
    const gyroSensitivity = 5.0;
    const noiseFloor = 0.09;
    _gyroSub =
        gyroscopeEventStream(samplingPeriod: SensorInterval.gameInterval)
            .listen((event) {
      if (!mounted) return;
      final now = DateTime.now();
      final dt = _lastGyroSampleTime == null
          ? 0.0
          : now.difference(_lastGyroSampleTime!).inMicroseconds / 1e6;
      _lastGyroSampleTime = now;
      if (event.z.abs() < noiseFloor) return;
      _tilt = (_tilt - event.z * gyroSensitivity * dt).clamp(-1.0, 1.0);
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
          // 2026-09-22 (round 3): real feedback, live - "sway left or
          // right until the phone is straight, then momentum would
          // gently continue upwards without left or right sway." This
          // is the actual decay the gyro listener above deliberately
          // doesn't do itself (gyro events can go quiet the instant the
          // phone is held still, which is exactly when decay needs to
          // keep running) - every frame, regardless of whether a gyro
          // event just fired, `_tilt` eases back toward 0 the same way
          // `_lean` eases toward `_tilt` below. tiltDecayRate 1.1 means
          // it takes roughly a second of holding the phone level to
          // settle back to dead center - gentle, not an instant snap.
          const tiltDecayRate = 1.1;
          _tilt -= _tilt * (1 - exp(-tiltDecayRate * dt));
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
