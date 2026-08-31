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
// 2026-08-31 revision, direct feedback on the first cut: needed longer
// to actually see, smaller shards, and the motion read as flying
// TOWARD the viewer rather than falling away - was driven by outward
// radial translation (each shard's x/y offset scaled with its distance
// from center). Reworked to (near-)zero horizontal drift, uniform
// downward fall (gravity, not position-dependent expansion), and a
// much deeper scale-down - shrinking + sinking reads as "falling back
// into the dark" rather than "exploding at the screen."
//
// 2026-08-31, second revision: still "doesn't look like smashing." Real
// bug, not just a description mismatch - each shard's own motion used
// Curves.easeIn (slow start, accelerating), which is backwards for an
// impact. A smash is fast/sudden at the moment of breaking and settles
// afterward - that's Curves.easeOut, not easeIn. The whole first cut
// was animating like something gently sinking rather than something
// that just got hit.

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
                    builder: (context, _) =>
                        CustomPaint(
                          size: Size.infinite,
                          painter: _ShatterPainter(animation.value),
                        ),
                  ),
                ),
              ],
            );
          },
        );
}

const _cols = 10;
const _rows = 20;

class _ShatterPainter extends CustomPainter {
  final double t;
  _ShatterPainter(this.t);

  static const _bg1 = Color(0xFFF3FBFA);
  static const _bg2 = Color(0xFFE1F5F0);

  @override
  void paint(Canvas canvas, Size size) {
    if (t >= 1) return;
    final w = size.width / _cols;
    final h = size.height / _rows;
    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        final fr = r / (_rows - 1);
        final bg = Color.lerp(_bg1, _bg2, fr)!;
        final cx = c - (_cols - 1) / 2;
        final cy = r - (_rows - 1) / 2;
        final dist = math.sqrt(cx * cx + cy * cy);
        final maxDist = math.sqrt(
            math.pow(_cols / 2, 2) + math.pow(_rows / 2, 2));
        // stagger: shards near center fall first, edges last - a ripple,
        // not a burst
        final delay = (dist / maxDist) * 0.4;
        var local = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
        local = Curves.easeOut.transform(local);

        final left = c * w;
        final top = r * h;
        // near-zero horizontal drift + a little per-shard jitter (not
        // position-scaled) + uniform downward fall = sinking away, not
        // radiating toward the viewer
        final jitter = ((c * 7 + r * 13) % 11 - 5) * 2.0;
        final outX = jitter * local;
        final outY = 130 * local;
        final rot = ((c * 5 + r * 3) % 9 - 4) * 0.06 * local;
        final scale = 1 - 0.9 * local;
        final opacity = 1 - local;
        if (opacity <= 0) continue;

        canvas.save();
        final center = Offset(left + w / 2 + outX, top + h / 2 + outY);
        canvas.translate(center.dx, center.dy);
        canvas.rotate(rot);
        canvas.scale(scale);
        canvas.translate(-w / 2, -h / 2);
        canvas.drawRect(
          Rect.fromLTWH(0, 0, w + 1, h + 1),
          Paint()..color = bg.withValues(alpha: opacity),
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ShatterPainter oldDelegate) =>
      oldDelegate.t != t;
}
