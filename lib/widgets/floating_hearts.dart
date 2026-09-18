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
import 'dart:math';
import 'package:flutter/material.dart';

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
  // 2026-09-18: real ask, live - "Can the hearts be interactive, like
  // a child waving a hand through balloons?" Local touch position,
  // null when nothing's touching - the painter pushes any heart
  // currently near this point sideways, away from it.
  Offset? _pointer;

  @override
  void initState() {
    super.initState();
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
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 2026-09-18: real ask, live - "Can the hearts be interactive, like
    // a child waving a hand through balloons?" No longer IgnorePointer -
    // first version used onHorizontalDragStart/Update, reasoning that a
    // horizontal-only drag recognizer wouldn't compete with the ancestor
    // SingleChildScrollView's vertical one. Real device feedback, same
    // day: "Hearts don't move, only the screen moves up and down with
    // finger swipes" - a real thumb swipe over a narrow 70px-wide column
    // is rarely purely horizontal, so the gesture arena kept awarding it
    // to the scroll view's recognizer instead, and the horizontal
    // recognizer here just never won at all.
    //
    // Listener instead of GestureDetector: raw pointer events, not a
    // gesture recognizer, so it never enters the arena and never
    // competes with the scroll view for anything - both get every
    // pointer event, unconditionally. translucent behavior keeps hit
    // testing passing through to the scroll view underneath.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) => setState(() => _pointer = e.localPosition),
      onPointerMove: (e) => setState(() => _pointer = e.localPosition),
      onPointerUp: (_) => setState(() => _pointer = null),
      onPointerCancel: (_) => setState(() => _pointer = null),
      child: SizedBox(
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
                pointer: _pointer),
            size: Size.infinite,
          ),
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
  // 2026-09-18: real ask, live - "hearts sway in the left or right
  // direction whilst moving up" in response to touch - local position
  // of an active horizontal drag, null when nothing's touching.
  final Offset? pointer;
  _HeartsPainter(
      {required this.t,
      required this.hearts,
      required this.color,
      this.quiet = false,
      this.pointer});

  // How far a heart reaches out to react - tuned so the reaction reads
  // as a hand passing near, not a pixel-precise trigger.
  //
  // 2026-09-18: real feedback, live - "I swiped the hearts but nothing
  // happens." With only 3-5 hearts staggered across the full 1050px
  // trail at any one moment, 45px was too tight a radius for a single
  // real swipe to reliably land near one - most of a short gesture's
  // touch path simply had no heart within reach. 45 -> 160 (most of the
  // 70px-wide column's height in practical reach, generous on the Y
  // axis where actual misses were happening) so a swipe anywhere in the
  // visible trail reacts, not just a pixel-precise one.
  static const _influenceRadius = 160.0;

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
      final p = pointer;
      if (p != null) {
        final dist = (Offset(x, y) - p).distance;
        if (dist < _influenceRadius) {
          // 2026-09-18 (round 2): real feedback, live - "Hearts have no
          // change" even after the gesture-routing fix (floating_hearts
          // now actually receives the touch). Real cause: a fingertip
          // covers most or all of this 70px-wide column, so a modest
          // px nudge stays hidden under the same finger that triggered
          // it. Blends toward the FAR edge of the box instead of a fixed
          // offset - close proximity (strength near 1) snaps the heart
          // almost all the way to the opposite edge, clearly outside a
          // fingertip's own footprint, not just a few px within it.
          final strength = 1 - dist / _influenceRadius;
          final edgeTarget = x >= p.dx ? size.width : 0.0;
          x = x + (edgeTarget - x) * strength;
        }
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
