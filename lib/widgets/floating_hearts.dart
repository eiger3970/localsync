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
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

class FloatingHearts extends StatefulWidget {
  final Color color;
  // How far above its own origin (y=0, bottom of this widget's box)
  // hearts rise before fading out.
  final double trailHeight;
  // 2026-09-17: fixed width, not double.infinity - this now lives in a
  // Positioned(left: 0, ...) with no matching `right`, which needs a
  // concrete width from its child rather than an unbounded one. Also
  // matches "stem from support" better - a narrow trail near the icon,
  // not a full-dialog-width spread.
  //
  // 2026-09-18: real feedback, live - "Hearts no change, just the
  // screen scrolls. The hearts might need a generous space around them
  // for user fingers to drag." 70 -> 140 - a real fingertip is roughly
  // 40-50px, so 70 left very little room either side of a heart to
  // actually initiate a touch that lands inside this column at all.
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
  double _tilt = 0;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  // 2026-09-18 (round 5): real ask, live - "hearts don't move at all"
  // (gyroscope round, sway specifically - the base rise/drift still
  // works). Tuning sensitivity/decay blindly hasn't converged in 4
  // rounds - this counts real events and shows the live raw value so
  // the next test gives direct ground truth (is the stream even
  // delivering anything at all, and if so, how big are the real
  // numbers) instead of another guess. Remove once this is resolved.
  int _gyroEventCount = 0;
  String? _gyroError;
  // 2026-09-18 (round 6): real ask, live - "No debug text." The
  // in-widget Positioned overlay (round 5) never actually showed up -
  // most likely painted-over by SUPPORT's own row content sitting at
  // nearly the same position in this dialog's Stack, or some other
  // layout quirk specific to this exact spot. A periodic SnackBar
  // (round 6) was tried next - real feedback, live (round 7): "error
  // behind About text, so I can't read it" - the About dialog is almost
  // certainly a showDialog() modal, whose own barrier/route sits above
  // the ScaffoldMessenger's SnackBar layer, so the SnackBar was
  // genuinely showing, just behind the dialog's own content.
  //
  // A raw OverlayEntry on the app's real ROOT overlay (rootOverlay:
  // true) is the one thing guaranteed to paint above everything else,
  // including any modal dialog currently open - nothing left between
  // this and the actual pixels on screen.
  Timer? _debugTimer;
  OverlayEntry? _debugOverlay;

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
    _gyroSub = gyroscopeEventStream().listen((event) {
      if (!mounted) return;
      _gyroEventCount++;
      _tilt = (_tilt + event.z * 0.4).clamp(-1.0, 1.0);
    }, onError: (e) {
      // 2026-09-18 (round 5): was silently swallowed - if motion access
      // is denied/unavailable on this exact device/signing setup, the
      // stream could error out immediately with zero visible sign at
      // all, indistinguishable from "just not moving enough."
      if (mounted) setState(() => _gyroError = '$e');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final overlay = Overlay.of(context, rootOverlay: true);
      final entry = OverlayEntry(
        builder: (_) => Positioned(
          top: 60,
          left: 16,
          right: 16,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(8),
              color: Colors.black,
              child: Text(
                _gyroError != null
                    ? 'GYRO ERR: $_gyroError'
                    : 'GYRO n=$_gyroEventCount tilt=${_tilt.toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ),
          ),
        ),
      );
      _debugOverlay = entry;
      overlay.insert(entry);
      _debugTimer = Timer.periodic(
          const Duration(milliseconds: 300), (_) => entry.markNeedsBuild());
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
        drift: (rng.nextDouble() - 0.5) * 0.6,
        driftPhase: rng.nextDouble() * 2 * pi,
      ),
    );
  }

  @override
  void dispose() {
    _debugTimer?.cancel();
    _debugOverlay?.remove();
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
        builder: (_, __) => CustomPaint(
          painter: _HeartsPainter(
              t: _ctrl.value,
              hearts: _hearts,
              color: widget.color,
              quiet: widget.quiet,
              tilt: _tilt),
          size: Size.infinite,
        ),
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
    for (final h in hearts) {
      final localT = (t * h.speed + h.startOffset) % 1.0;
      // y=size.height (the widget's own bottom edge, right at SUPPORT's
      // row) at localT=0, rising to y=0 (top of this widget's box,
      // above the row) at localT=1 - a real, local trail, not a
      // fraction of some distant ancestor's height.
      final y = size.height * (1 - localT);
      final sway = sin(localT * 2 * pi + h.driftPhase) * h.drift;
      var x = (size.width * (h.x + sway)).clamp(0.0, size.width);
      // 2026-09-18 (round 3): real ask, live - "the sway should just
      // sway to the edge of the screen or until I stop tilting the
      // phone." A fixed px offset (round 2) could still land short of
      // the real edge depending on where a heart's own ambient drift
      // put it. Blends toward whichever edge `tilt`'s sign points at
      // instead, with blend strength equal to |tilt| - at full tilt
      // this snaps all the way to the true edge regardless of starting
      // position, not just partway there.
      if (tilt != 0) {
        final edgeTarget = tilt > 0 ? size.width : 0.0;
        x = x + (edgeTarget - x) * tilt.abs();
      }
      // Fade in near the bottom (origin), fade out near the top - never
      // pops in/out abruptly mid-rise.
      final fadeIn = localT < 0.15 ? localT / 0.15 : 1.0;
      final fadeOut = localT > 0.78 ? (1 - localT) / 0.22 : 1.0;
      final opacity = (fadeIn * fadeOut).clamp(0.0, 1.0);
      if (opacity <= 0.02) continue;
      _paintHeartGlyph(canvas, Offset(x, y), h.size,
          color.withValues(alpha: opacity * (quiet ? 0.3 : 0.5)));
    }
  }

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
