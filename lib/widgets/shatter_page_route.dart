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
//
// 2026-08-31, fourth revision, direct feedback: "was better before" -
// the bottom-right impact-origin version (previous revision) was a
// regression from the fall-away version before it. Reworked again, per
// explicit direction this time: not shards falling away from a point,
// but every shard COLLAPSING/CONVERGING toward one point - the phone's
// position in the preview screens' own illustration (roughly its
// upper-left area) - shrinking as it arrives, like the whole scene
// getting pulled back into the phone. Nearer shards reach it soonest,
// farther ones (the desktop side) take longest, same stagger idea as
// before but aimed at a destination instead of radiating from an
// origin.
//
// 2026-08-31, fifth revision, direct feedback: "looks like it's being
// pulled, needs to look natural... shrinks into the distance." Real
// fix: the previous version lerped 2D screen position toward the
// target and shrank scale as two SEPARATE animations - that's exactly
// what a sideways drag looks like. Switched to actual perspective
// math: a single "depth" value grows over time, and BOTH position and
// scale shrink by the same 1/depth factor - the same relationship a
// real camera has with an object receding away from it toward a
// vanishing point. Same formula, one variable, looks like distance
// instead of a drag.

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
    // approximate on-screen position of the phone icon in the preview
    // screens' own PhoneToDesktopFlow illustration (upper-left area of
    // the centered illustration block) - everything collapses toward
    // this point rather than falling away from one.
    final target = Offset(size.width * 0.20, size.height * 0.42);
    final corners = [
      const Offset(0, 0),
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ];
    final maxDist =
        corners.map((c) => (c - target).distance).reduce(math.max);

    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        final fr = r / (_rows - 1);
        final bg = Color.lerp(_bg1, _bg2, fr)!;
        final left = c * w;
        final top = r * h;
        final restCenter = Offset(left + w / 2, top + h / 2);

        // stagger: shards nearest the phone collapse into it first
        // (short trip), the desktop side last (long trip)
        final dist = (restCenter - target).distance;
        final delay = (dist / maxDist) * 0.4;
        var local = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
        local = Curves.easeOut.transform(local);
        if (local >= 1) continue;

        // real perspective, not a 2D drag: position AND scale both
        // shrink by the same 1/depth factor as "depth" increases, the
        // way an object actually behaves receding away from a camera
        // toward a vanishing point. Lerping position while separately
        // shrinking scale (the previous version) reads as being
        // dragged sideways - this reads as moving away into the
        // distance, because it's the same math a real camera would see.
        final depth = 1 + 30 * local;
        final scale = 1 / depth;
        if (scale <= 0.02) continue;
        final pos = target + (restCenter - target) / depth;
        final rot = ((c * 5 + r * 3) % 9 - 4) * 0.08 * local;

        canvas.save();
        canvas.translate(pos.dx, pos.dy);
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
