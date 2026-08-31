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
//
// 2026-08-31, third revision, direct feedback: "pieces are faded
// translucent squares... immediately switch... to the black... screen,
// but the screen needs to be white with the transition smashing into
// the black screen." Two real fixes: (1) shards were fading their own
// ALPHA out (opacity = 1-local) as they shrank - that reads as
// dissolving/translucent, not solid pieces breaking away. They're now
// fully opaque the whole time they're drawn, and simply stop being
// drawn once they've shrunk past visibility - no fade. (2) the overlay
// used to sit directly on top of the real incoming page, so mid-
// transition you'd see LinkingScreen's actual (possibly busy) UI
// bleeding through - now there's a solid black layer between the
// shards and the real content, so what's revealed as shards clear away
// is clean black, and the real page only appears once the whole
// overlay finishes (t>=1), not gradually through the cracks.

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

const _cols = 10;
const _rows = 20;

class _ShatterPainter extends CustomPainter {
  final double t;
  _ShatterPainter(this.t);

  static const _bg1 = Color(0xFFF3FBFA);
  static const _bg2 = Color(0xFFE1F5F0);

  @override
  void paint(Canvas canvas, Size size) {
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
        final scale = 1 - 0.97 * local;
        // fully opaque, solid pastel the whole time it's visible - no
        // alpha fade (that read as "faded translucent squares"). It
        // just stops being drawn once it's shrunk to nothing.
        if (local >= 1 || scale <= 0.02) continue;

        canvas.save();
        final center = Offset(left + w / 2 + outX, top + h / 2 + outY);
        canvas.translate(center.dx, center.dy);
        canvas.rotate(rot);
        canvas.scale(scale);
        canvas.translate(-w / 2, -h / 2);
        canvas.drawRect(
          Rect.fromLTWH(0, 0, w + 1, h + 1),
          Paint()..color = bg,
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ShatterPainter oldDelegate) =>
      oldDelegate.t != t;
}
