// widgets/shatter_page_route.dart
//
// The transition for the one moment the welcome flow's pastel world
// actually meets the real app's dark one. Used for the one
// welcome->real-app handoff (the preview screens' SwapGifSwipeConfirm
// into LinkingScreen), not a general-purpose route - keep it there.
//
// [revisions 1-8 covered a glass-shatter concept, then a falling-tile
// grid with a diagonal wave sweep - through many rounds without
// landing. See git history if that log is ever needed.]
//
// 2026-09-01, ninth revision: "fade into background, not swipe around
// the screen like currently" - dropped the tile grid entirely for a
// plain full-screen fade to black. Real regression: "flashes and
// fades... nothing like what I want."
//
// 2026-09-01, tenth revision - asked directly rather than guessing an
// eleventh time: "cool effect like glass being smashed, so white broken
// pieces fall into the background, taking the user into the black app."
// Three real ingredients, all present now: (1) an impact - pieces start
// moving in a tight window near t=0 (small random spread, not a wide
// stagger and not a directional wave), reading as one smash rather than
// a drip; (2) fall - accelerating downward motion, not fade-in-place;
// (3) into the background - each piece also scales down around its own
// center as it falls, the actual depth cue for "receding," not just
// alpha. Deliberately still a plain rect grid, not real crack-pattern
// geometry - that was already tried (revisions 1-7) and explicitly
// dropped for being "too complicated."
//
// 2026-09-01, eleventh revision: "falls to bottom of screen, but should
// fall getting smaller into the distance, not up, down, left or right."
// The y-offset from revision ten WAS the fall - dropped entirely. Pure
// in-place shrink now, no positional movement in any direction; scale
// alone carries the whole "receding into the distance" read.

// 2026-09-24, twelfth revision - launch check list, real ask, live:
// "Transition is the install white screen, which transitions to black,
// currently with fading squares, but I want breaking glass." The
// eleventh revision's shrinking rect grid is the "fading squares." Real
// glass now, keeping every rule the earlier rounds settled on:
//  - an impact first (rev 10): a crack web - radial cracks plus rings,
//    all jittered - spreads out from one point over the first ~15%;
//  - then the pieces recede into the distance (rev 11): each shard
//    shrinks toward its own centre and tumbles (rotation), nothing
//    travels across the screen in any direction;
//  - clean black revealed behind (rev 9's black, never the page's UI).
// Irregular shard polygons (quads between neighbouring cracks and rings,
// some split into triangles) are what make it read as glass, not tiles.
// Fixed seed - identical crack pattern every frame and every run.

import 'dart:math' as math;
import 'package:flutter/material.dart';

class ShatterPageRoute<T> extends PageRouteBuilder<T> {
  ShatterPageRoute({required WidgetBuilder builder})
      : super(
          transitionDuration: const Duration(milliseconds: 1500),
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return Stack(
              children: [
                child,
                IgnorePointer(
                  child: AnimatedBuilder(
                    animation: animation,
                    builder: (context, _) {
                      final t = animation.value;
                      if (t >= 1) return const SizedBox.shrink();
                      return Stack(
                        children: [
                          // what's revealed as pieces fall away is
                          // clean black, never the real page's own UI
                          Container(color: Colors.black),
                          CustomPaint(
                            size: Size.infinite,
                            painter: _GlassSmashPainter(t),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
}

class _Shard {
  final List<Offset> pts; // fractions of the screen (0..1), not pixels
  final Offset centroid;
  final double delay; // 0..~0.3 - inner shards go first
  final double spin; // radians at full recession, signed
  _Shard(this.pts, this.centroid, this.delay, this.spin);
}

const _impact = Offset(0.5, 0.42);
const _crackPhase = 0.2; // share of the transition spent cracking

final List<_Shard> _shards = () {
  final rand = math.Random(11);
  const rays = 13;
  const rings = [0.06, 0.15, 0.28, 0.45, 0.68, 1.0, 1.5];
  // Jittered ray angles, sorted, so neighbouring rays never cross.
  final angles = List.generate(
      rays, (i) => (i + 0.2 + rand.nextDouble() * 0.6) * 2 * math.pi / rays);
  // vertex(i, k): ray i, ring k, radius jittered per vertex.
  final radii = List.generate(
      rays, (_) => rings.map((r) => r * (0.82 + rand.nextDouble() * 0.36)).toList());
  Offset v(int i, int k) {
    final a = angles[i % rays];
    final r = radii[i % rays][k];
    // Screens are ~2x taller than wide - stretch x so the web fills it.
    return Offset(_impact.dx + math.cos(a) * r * 1.0,
        _impact.dy + math.sin(a) * r * 0.62);
  }

  final out = <_Shard>[];
  void add(List<Offset> pts) {
    var cx = 0.0, cy = 0.0;
    for (final p in pts) {
      cx += p.dx;
      cy += p.dy;
    }
    final c = Offset(cx / pts.length, cy / pts.length);
    final dist = (c - _impact).distance;
    out.add(_Shard(
      pts,
      c,
      (dist * 0.35).clamp(0.0, 0.28) + rand.nextDouble() * 0.04,
      (rand.nextBool() ? 1 : -1) * (0.4 + rand.nextDouble() * 0.9),
    ));
  }

  for (var i = 0; i < rays; i++) {
    add([_impact, v(i, 0), v(i + 1, 0)]);
    for (var k = 0; k < rings.length - 1; k++) {
      final q = [v(i, k), v(i + 1, k), v(i + 1, k + 1), v(i, k + 1)];
      if (rand.nextDouble() < 0.45) {
        add([q[0], q[1], q[2]]);
        add([q[0], q[2], q[3]]);
      } else {
        add(q);
      }
    }
  }
  return out;
}();

class _GlassSmashPainter extends CustomPainter {
  final double t;
  _GlassSmashPainter(this.t);

  static const _bg1 = Color(0xFFF3FBFA);
  static const _bg2 = Color(0xFFE1F5F0);
  static const _crack = Color(0xFF0E4A44); // the welcome palette's dark teal

  @override
  void paint(Canvas canvas, Size size) {
    Offset px(Offset f) => Offset(f.dx * size.width, f.dy * size.height);
    final impactPx = px(_impact);
    final maxR = size.longestSide * 1.1;

    if (t < _crackPhase) {
      // Intact pane with cracks racing outward from the impact.
      final grow = Curves.easeInOut.transform(t / _crackPhase);
      canvas.drawRect(
          Offset.zero & size,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_bg1, _bg2],
            ).createShader(Offset.zero & size));
      canvas.save();
      canvas.clipPath(Path()
        ..addOval(Rect.fromCircle(center: impactPx, radius: maxR * grow)));
      final crackPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = _crack.withValues(alpha: 0.55);
      final glintPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Colors.white.withValues(alpha: 0.9);
      for (final s in _shards) {
        final path = Path()..addPolygon(s.pts.map(px).toList(), true);
        canvas.drawPath(path.shift(const Offset(0.8, 0.8)), glintPaint);
        canvas.drawPath(path, crackPaint);
      }
      canvas.restore();
      return;
    }

    // Shards recede: shrink toward their own centre and tumble.
    final phaseT = (t - _crackPhase) / (1 - _crackPhase);
    for (final s in _shards) {
      var local = ((phaseT - s.delay) / (1 - s.delay)).clamp(0.0, 1.0);
      local = Curves.easeIn.transform(local);
      final alpha = (1 - local * local).clamp(0.0, 1.0);
      if (alpha <= 0.02) continue;
      final c = px(s.centroid);
      final scale = 1.0 - 0.85 * local;
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(s.spin * local);
      canvas.scale(scale);
      canvas.translate(-c.dx, -c.dy);
      final path = Path()..addPolygon(s.pts.map(px).toList(), true);
      final bg = Color.lerp(_bg1, _bg2, s.centroid.dy.clamp(0.0, 1.0))!;
      canvas.drawPath(path, Paint()..color = bg.withValues(alpha: alpha));
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0
            ..color = Colors.white.withValues(alpha: alpha * 0.9));
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = _crack.withValues(alpha: alpha * 0.55));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _GlassSmashPainter oldDelegate) =>
      oldDelegate.t != t;
}
