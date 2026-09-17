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
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
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
      _velocities = [
        for (final p in pts)
          (Offset(p.dx - 0.5, p.dy - 0.5) * (0.7 + rng.nextDouble() * 0.6)) +
              Offset(rng.nextDouble() - 0.5, rng.nextDouble() - 0.5) * 0.35,
      ];
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
        fontWeight: FontWeight.w700,
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
    const burstEnd = 0.55;
    if (t > burstEnd) return;
    final burstT = t <= holdEnd ? 0.0 : (t - holdEnd) / (burstEnd - holdEnd);
    final fade = pow(1 - burstT, 1.6).toDouble();
    if (fade <= 0.02) return;
    final paint = Paint()..color = color.withValues(alpha: fade.clamp(0, 1));
    for (var i = 0; i < base.length; i++) {
      final p = base[i];
      final v = vel[i];
      final dx = (p.dx + v.dx * burstT) * size.width;
      final dy = (p.dy + v.dy * burstT) * size.height;
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
