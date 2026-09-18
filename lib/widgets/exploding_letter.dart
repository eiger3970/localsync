// widgets/exploding_letter.dart
//
// 2026-09-17: real ask, live - the password-discarded row's icon went
// through several static Material Icon tries (delete_outline read as
// "a bin a hacker could steal from," auto_awesome read as "magic
// stars") before landing on a real animated idea: a letter bursting
// into dust, looping continuously while the info panel is open.
//
// Pure CustomPainter, no image/SVG asset at all - same reasoning as
// ShreddingPasswordField's own fade-and-drift shred animation
// (widgets/shredding_password_field.dart), which already proves this
// exact "real Flutter animation, not a baked asset" pattern works in
// this app. Confirmed with the user: this technique is genuinely
// lighter than shipping a GIF or SVG (zero file weight, and it
// recolors automatically with whichever skin/accent is active) - but
// only for a shape simple enough to describe as points in code. It
// doesn't generalize to replacing real illustrated artwork.
//
// 2026-09-17, corrected same day - real feedback, live: "P doesn't
// look like a regular P and doesn't explode like the original
// example." The original Python/PIL prototype (shown for comparison
// before this was ever built for real) sampled real per-pixel glyph
// coverage from a rendered font. The first Flutter version used a
// hand-rolled parametric point-set (a vertical stroke + an approximate
// arc) as a stand-in - it never actually matched. Now renders the real
// letter with Flutter's own TextPainter, reads back the rasterized
// pixels via dart:ui, and samples particle positions from wherever the
// glyph actually has ink - the same technique the approved Python
// version used, just running in Dart instead of PIL.
import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class ExplodingLetter extends StatefulWidget {
  final String letter;
  final Color color;
  final double size;
  const ExplodingLetter({
    super.key,
    required this.letter,
    required this.color,
    this.size = 20,
  });

  @override
  State<ExplodingLetter> createState() => _ExplodingLetterState();
}

class _ExplodingLetterState extends State<ExplodingLetter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  List<Offset>? _basePoints;
  List<Offset>? _velocities;

  @override
  void initState() {
    super.initState();
    // 2026-09-17: real feedback, live - "make the disintegration longer
    // so user sees that." 1400ms total (with an 18% hold) read as a
    // quick pop in the real continuous loop, easy to miss between
    // resets. Nearly doubled, and the hold/burst split below was
    // rebalanced too - not just a longer total, the dissolve itself
    // needs to read as gradual.
    //
    // 2026-09-18: real feedback, live (round 2) - "make the fade away
    // take more time, it's too quick." Bumped again, 2600ms -> 3400ms -
    // paired with widening the burst/fade window itself in
    // _ExplodePainter (burstEnd, below) so the extra time actually
    // goes into a slower fade, not just a longer blank pause.
    //
    // 2026-09-18: real feedback, live (round 3) - "make the fade away
    // take more time... try explosion, so P blows apart to all edges of
    // the graphic space." Two separate fixes, not just another duration
    // bump: the fade curve in _ExplodePainter now holds near-opaque
    // through most of the burst so the scattering dust is actually
    // visible while it travels (round 2 sped the fade AND spread up
    // together but the particles were already near-invisible before
    // they'd traveled far), and particle positions are now clamped to
    // the widget's own bounds so the burst visibly reaches the real
    // edges instead of overshooting into invisible (near-zero-alpha,
    // off-canvas) territory. 3400ms -> 4200ms on top of that.
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..repeat();
    unawaited(_samplePoints());
  }

  // One-time async cost, not per-frame - renders as a blank box for the
  // ~1 frame this takes on first build, imperceptible in practice.
  Future<void> _samplePoints() async {
    final pts = await _glyphPoints(widget.letter);
    if (!mounted) return;
    final rng = Random(7);
    setState(() {
      _basePoints = pts;
      // 2026-09-18 (round 5): real ask, live - "P is still fading, needs
      // to explode from centre to outer edges." Velocity used to be the
      // particle's own offset from center scaled by a multiplier -
      // proportional to starting distance, so points near the glyph's
      // own visual middle (much of a P's vertical stroke) barely moved
      // at all and read as fading in place rather than launching
      // outward. Now a proper radial burst: every particle gets the
      // SAME speed range, direction only, so every point - center-ish
      // or not - travels a real, similar distance toward the edges.
      _velocities = [for (final p in pts) _radialVelocity(p, rng)];
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = _basePoints;
    final vel = _velocities;
    if (base == null || vel == null) {
      return SizedBox(width: widget.size, height: widget.size);
    }
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => CustomPaint(
          painter: _ExplodePainter(
            t: _ctrl.value,
            base: base,
            vel: vel,
            color: widget.color,
          ),
        ),
      ),
    );
  }
}

/// Renders [letter] with Flutter's own text rendering, reads back the
/// rasterized pixels, and returns normalized (0..1) positions of every
/// pixel the glyph actually covers - a real point cloud of the letter's
/// true shape, not an approximation.
Future<List<Offset>> _glyphPoints(String letter) async {
  // Rendered oversized (a fixed resolution regardless of the on-screen
  // display size, which might be as small as 15-20px - too few real
  // pixels to sample a recognizable shape from directly).
  const renderSize = 96.0;
  // 2026-09-17: real bug, caught before shipping - a bare TextPainter
  // built outside any widget tree/Theme doesn't inherit this app's
  // default font, and with no fontFamily specified it rendered as a
  // solid tofu block (real advance-width metrics, but no actual glyph
  // outline) - sampling that gave a uniform grid, not a letter shape.
  // Explicit 'Roboto' (Flutter's own bundled Material default, real on
  // every platform including iOS) fixes it - confirmed by rendering
  // the raw offscreen image directly and looking at it, not just
  // trusting the sampled points.
  final textPainter = TextPainter(
    text: TextSpan(
      text: letter,
      style: const TextStyle(
        fontFamily: 'Roboto',
        fontSize: renderSize * 0.82,
        // 2026-09-18 (round 6): real feedback, live - "P needs a clearer
        // gap in the P part of the P." w700 (bold) made the bowl's own
        // stroke thick enough to nearly close its hole, especially once
        // subsampled to 60 points - reads as a near-solid blob rather
        // than a P with a real hole in it. w500 keeps the letter
        // recognizable while opening that hole back up.
        fontWeight: FontWeight.w500,
        color: Color(0xFFFFFFFF),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, renderSize, renderSize));
  // 2026-09-17: real bug, caught before shipping - checking the alpha
  // channel after toImage() came back fully opaque EVERYWHERE (a
  // uniform grid of sampled points covering the whole canvas, not a
  // "P" shape at all), not just where the glyph has ink. Whatever the
  // exact compositing reason, alpha isn't a reliable transparency
  // signal here. Explicit black fill first, so background vs. text is
  // unambiguous - now sampling on RGB brightness (white text on black)
  // instead of alpha, which can't have this ambiguity.
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, renderSize, renderSize),
    Paint()..color = const Color(0xFF000000),
  );
  final offset = Offset(
    (renderSize - textPainter.width) / 2,
    (renderSize - textPainter.height) / 2,
  );
  textPainter.paint(canvas, offset);
  final picture = recorder.endRecording();
  final image = await picture.toImage(renderSize.toInt(), renderSize.toInt());
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  if (byteData == null) return _fallbackPoints();

  final bytes = byteData.buffer.asUint8List();
  final w = renderSize.toInt();
  final h = renderSize.toInt();
  final candidates = <Offset>[];
  // Every few pixels, not every single one - enough density to read as
  // a solid letter once drawn as small dots, without hundreds of near-
  // duplicate points costing real per-frame paint work for no visible
  // gain.
  const stride = 3;
  for (var y = 0; y < h; y += stride) {
    for (var x = 0; x < w; x += stride) {
      final red = bytes[(y * w + x) * 4];
      if (red > 128) candidates.add(Offset(x / w, y / h));
    }
  }
  if (candidates.isEmpty) return _fallbackPoints();
  // Cap the particle count for paint-cost reasons, same rough budget as
  // the original hand-rolled version - subsample evenly rather than
  // truncate, so the cap doesn't bias toward one corner of the letter.
  const maxPoints = 60;
  if (candidates.length <= maxPoints) return candidates;
  final step = candidates.length / maxPoints;
  return [for (var i = 0; i < maxPoints; i++) candidates[(i * step).floor()]];
}

/// Only reached if glyph rasterization genuinely fails (byteData null) -
/// a plain circle outline so something still renders rather than
/// nothing.
List<Offset> _fallbackPoints() => [
      for (double a = 0; a < 2 * pi; a += pi / 10)
        Offset(0.5 + 0.35 * cos(a), 0.5 + 0.35 * sin(a)),
    ];

/// 2026-09-18 (round 5): a true radial burst direction/speed for [p] -
/// same speed range regardless of how close [p] already sits to the
/// box's center (0.5, 0.5), so every particle travels a real, similar
/// distance outward instead of barely moving when it happens to start
/// near the middle. A point that lands exactly on center (vanishingly
/// rare for real glyph pixels, but not impossible) gets a random
/// direction instead of an undefined one.
Offset _radialVelocity(Offset p, Random rng) {
  final dx = p.dx - 0.5, dy = p.dy - 0.5;
  final dist = sqrt(dx * dx + dy * dy);
  final angle = dist > 0.01 ? atan2(dy, dx) : rng.nextDouble() * 2 * pi;
  final speed = 0.65 + rng.nextDouble() * 0.35;
  return Offset(cos(angle), sin(angle)) * speed;
}

class _ExplodePainter extends CustomPainter {
  final double t; // 0..1, loops via AnimationController.repeat()
  final List<Offset> base;
  final List<Offset> vel;
  final Color color;
  _ExplodePainter({
    required this.t,
    required this.base,
    required this.vel,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Holds the letter shape briefly, then bursts outward and fades -
    // the hold gives the eye a moment to register "a letter" before it
    // vanishes, matching the actual claim ("used once, then gone").
    //
    // 2026-09-17: real feedback, live - "make the disintegration longer
    // so user sees that." Two changes together, not just the longer
    // total AnimationController duration above: fade now eases (stays
    // near-opaque through most of the spread, only dropping off near
    // the very end) instead of a constant linear fade-with-spread, so
    // the scattering dust itself stays visible longer instead of
    // fading at the same rate it moves.
    // 2026-09-18: real feedback, live - "P needs to say gone for a
    // moment before reappearing." burstT/fade used to reach exactly 0
    // right as t wrapped back to 0 (AnimationController.repeat()'s
    // cycle boundary) - the letter re-formed the very same instant it
    // finished fading, no actual gap between "gone" and "back." Burst
    // now completes by burstEnd instead of riding all the way to t=1 -
    // everything from burstEnd to the wrap is a real blank pause before
    // the hold phase (and the letter) begins again.
    const holdEnd = 0.18;
    // 2026-09-18: real feedback, live (round 2) - "make the fade away
    // take more time, it's too quick." 0.55 -> 0.68, combined with the
    // longer 3400ms total above, roughly doubles the fade window's real
    // wall-clock time (~962ms -> ~1700ms) while still leaving a real
    // blank pause afterward (~1088ms, close to the previous ~1170ms) -
    // not stealing the whole increase from the "gone for a moment" gap
    // that was just added.
    //
    // 2026-09-18 (round 3): 0.68 -> 0.78, on top of the 4200ms total
    // above, so the visible burst window is longer still.
    const burstEnd = 0.78;
    if (t > burstEnd) return;
    final burstT = t <= holdEnd ? 0.0 : (t - holdEnd) / (burstEnd - holdEnd);
    // 2026-09-18 (round 3): pow exponent 1.6 -> 0.6 - a flatter curve
    // that stays close to fully opaque through most of burstT instead
    // of dropping off early, so the dust is genuinely visible while it
    // travels outward, not just at the moment it starts bursting.
    final fade = pow(1 - burstT, 0.6).toDouble();
    if (fade <= 0.02) return;
    for (var i = 0; i < base.length; i++) {
      final p = base[i];
      final v = vel[i];
      // 2026-09-18 (round 3): real ask, live - "P blows apart to all
      // edges of the graphic space." Positions used to travel well past
      // 0..1 (unclamped, so most particles ended up off-canvas and
      // invisible by the time they'd spread that far) - kept unclamped
      // here (rawX/rawY) so the edge-fade below can tell "reached the
      // edge" from "overshot past it," and clamped only for the actual
      // draw position, so an overshooting particle still visibly stops
      // right at the real edge instead of vanishing early.
      final rawX = p.dx + v.dx * burstT;
      final rawY = p.dy + v.dy * burstT;
      // 2026-09-18 (round 4): real ask, live - "more visible with bits
      // spreading to edges, maybe fade away near edges." Round 3's clamp
      // alone made edge-reaching particles sit fully solid right at the
      // boundary until the global time-based fade caught up - reads as
      // dust "sticking" to the wall. This fades each particle out
      // individually as it nears/passes an edge (within the last 15% of
      // the box, scaled by however far past it it's overshot), on top of
      // the existing time-based fade - so the burst visibly dissolves
      // right at the edges instead of stacking against them.
      final edgeDist =
          [rawX, 1 - rawX, rawY, 1 - rawY].reduce((a, b) => a < b ? a : b);
      final edgeFade = (edgeDist / 0.15).clamp(0.0, 1.0);
      final alpha = (fade * edgeFade).clamp(0.0, 1.0);
      if (alpha <= 0.02) continue;
      final paint = Paint()..color = color.withValues(alpha: alpha);
      final dx = rawX.clamp(0.0, 1.0) * size.width;
      final dy = rawY.clamp(0.0, 1.0) * size.height;
      // 2026-09-17: real bug, caught before it shipped further - "P is
      // fading away, I don't see the explosion." /32 with a 0.3-1.8
      // clamp was tuned against the 90px preview size, but the real
      // PasswordInfoRow usage is only 15px - at that size the divisor
      // gave a radius that clamped to ~0.3-0.47px the whole time,
      // essentially invisible dots regardless of burstT, reading as a
      // fade rather than a burst. /10 with a 1.0-3.5px floor stays
      // visible at the actual size this is used at.
      final r = ((1.0 - burstT * 0.6) * (size.width / 10)).clamp(1.0, 3.5);
      canvas.drawCircle(Offset(dx, dy), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ExplodePainter old) => old.t != t;
}
