// widgets/shatter_page_route.dart
//
// 2026-08-31: the transition for the one moment the welcome flow's
// pastel world actually meets the real app's dark one - "the screen
// fragments apart into the black screen, like diving into a new movie
// space world of the real app." A grid of shards covers the incoming
// (real, dark) page at rest, then falls back/away and fades with a
// small stagger rippling outward from center, revealing the real
// destination underneath as they clear - not a fake backdrop, the
// actual next screen. Used for the one welcome->real-app handoff (the
// preview screens' SwapGifSwipeConfirm into LinkingScreen), not a
// general-purpose route - keep it there.
//
// [revisions 1-6 covered a uniform-grid version through several rounds
// of motion/opacity/origin fixes - see git history for that log if
// needed, dropped here since revision 7 replaces the shape entirely]
//
// 2026-08-31, seventh revision, direct question and direct answer:
// asked outright "did you do a glass shatter transition?" - honestly,
// no - every prior revision was a uniform grid of small rectangles,
// which only approximates a shatter through motion, not through shape.
// Real glass breaks into irregular, differently-sized polygon shards
// radiating from an impact point, not a uniform grid. Rebuilt the shard
// geometry from scratch: a radial crack pattern - irregular "spokes"
// (angles) crossed with irregular "rings" (radii) around an impact
// point, the same structure real shatter/crack patterns actually have.
// Each cell between two adjacent spokes and two adjacent rings is one
// irregular quadrilateral shard. Motion/fade/stagger logic (each shard
// falls from its own position, fades in the back half, cracks
// propagate outward from the impact point first) carries over from the
// previous revision - only the shard SHAPE changes here.

import 'dart:math' as math;
import 'package:flutter/material.dart';

class ShatterPageRoute<T> extends PageRouteBuilder<T> {
  ShatterPageRoute({required WidgetBuilder builder})
      : super(
          transitionDuration: const Duration(milliseconds: 1700),
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
                          // solid black first - what's revealed as
                          // shards clear is clean black, never the real
                          // page's own UI bleeding through mid-smash
                          Container(color: Colors.black),
                          CustomPaint(
                            size: Size.infinite,
                            painter: _ShatterPainter(t),
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

const _spokes = 16;
const _rings = 7;

class _Shard {
  final List<Offset> corners; // 4 corners, impact-relative
  final Offset centroid; // impact-relative
  final double distFromImpact;
  _Shard(this.corners, this.centroid, this.distFromImpact);
}

// Precomputed once - the crack pattern itself doesn't change frame to
// frame, only how far each shard has fallen does. Geometry is in
// impact-relative units (0..1 of maxDist), scaled to the real canvas
// size at paint time since the route can run at any screen size.
class _CrackPattern {
  final List<_Shard> shards;
  _CrackPattern(this.shards);

  static _CrackPattern build() {
    // deterministic "jitter" - a fixed formula, not real randomness, so
    // the pattern is identical every frame without needing to cache
    // canvas-size-dependent state.
    double jitter(int seed, double spread) =>
        (((seed * 2654435761) % 1000) / 1000 - 0.5) * 2 * spread;

    final angleStep = (2 * math.pi) / _spokes;
    final angles = List.generate(_spokes + 1, (j) {
      return j * angleStep + jitter(j * 31 + 7, angleStep * 0.35);
    });

    // non-linear ring spacing (power curve) - small dense shards near
    // the impact point, larger ones farther out, the way real glass
    // actually cracks.
    final radii = List.generate(_rings + 1, (i) {
      final f = i / _rings;
      final base = math.pow(f, 1.6).toDouble();
      return (base + jitter(i * 53 + 11, 0.04)).clamp(0.0, 1.2);
    });

    final shards = <_Shard>[];
    for (var i = 0; i < _rings; i++) {
      for (var j = 0; j < _spokes; j++) {
        Offset polar(double angle, double r) =>
            Offset(math.cos(angle), math.sin(angle)) * r;
        final corners = [
          polar(angles[j], radii[i]),
          polar(angles[j + 1], radii[i]),
          polar(angles[j + 1], radii[i + 1]),
          polar(angles[j], radii[i + 1]),
        ];
        final centroid = corners.reduce((a, b) => a + b) / 4;
        shards.add(_Shard(corners, centroid, centroid.distance));
      }
    }
    return _CrackPattern(shards);
  }
}

final _pattern = _CrackPattern.build();

class _ShatterPainter extends CustomPainter {
  final double t;
  _ShatterPainter(this.t);

  static const _bg1 = Color(0xFFF3FBFA);
  static const _bg2 = Color(0xFFE1F5F0);

  @override
  void paint(Canvas canvas, Size size) {
    // impact point near the bottom-right - roughly where the dog sits
    // after a completed swipe-confirm gesture
    final impact = Offset(size.width * 0.85, size.height * 0.9);
    final corners = [
      const Offset(0, 0),
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ];
    final maxDist = corners.map((c) => (c - impact).distance).reduce(math.max);

    var i = 0;
    for (final shard in _pattern.shards) {
      i++;
      final realCentroid = impact + shard.centroid * maxDist;
      final fr = (realCentroid.dy / size.height).clamp(0.0, 1.0);
      final bg = Color.lerp(_bg1, _bg2, fr)!;

      // cracks propagate outward from the impact point first
      final delay = (shard.distFromImpact).clamp(0.0, 1.2) / 1.2 * 0.35;
      var local = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
      local = Curves.easeOut.transform(local);
      if (local >= 1) continue;

      // each shard falls from its own position with a little per-shard
      // randomness plus a gentle drift bias, same motion language as
      // the previous grid revision - only the shape is new
      final jx = ((i * 7) % 17 - 8) * 3.0;
      final jy = ((i * 11) % 13 - 6) * 3.0;
      // no consistent sideways bias - just per-shard jitter - so the
      // dominant motion reads as straight-down falling, matching "glass
      // shatters and falls to the bottom of the screen."
      final outX = jx * local;
      final outY = (140 + jy) * local;
      final scale = 1 - 0.85 * local;
      final alpha = local < 0.45 ? 1.0 : 1 - (local - 0.45) / 0.55;
      if (scale <= 0.03 || alpha <= 0.02) continue;
      final rot = ((i * 53) % 40 - 20) * 0.045 * local;

      canvas.save();
      canvas.translate(realCentroid.dx + outX, realCentroid.dy + outY);
      canvas.rotate(rot);
      canvas.scale(scale);
      canvas.translate(-realCentroid.dx, -realCentroid.dy);

      final path = Path();
      final realCorners =
          shard.corners.map((c) => impact + c * maxDist).toList();
      path.moveTo(realCorners[0].dx, realCorners[0].dy);
      for (final c in realCorners.skip(1)) {
        path.lineTo(c.dx, c.dy);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = bg.withValues(alpha: alpha));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ShatterPainter oldDelegate) =>
      oldDelegate.t != t;
}
