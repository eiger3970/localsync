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
//
// 2026-08-31, sixth revision, direct feedback: "looks like some
// futuristic wizz around... I just need the effect like breaking glass
// and it fades into the background black screen." Root cause of the
// "wizz": EVERY shard converging on the exact same point is what reads
// as a portal/warp-speed effect, not a break - real glass shards don't
// all fly to one spot. Reverted to each shard falling independently
// from its OWN rest position (this is what the earlier "much better"
// version did, before later revisions kept re-introducing a single
// convergence/origin point) - with a mild leftward/upward drift bias
// (loosely toward the phone) rather than a literal shared destination.
// Also restored an alpha fade this time, deliberately - the reason it
// was removed three revisions ago (reads as "faded translucent
// squares") no longer applies now that there's a solid black layer
// underneath: fading now reveals clean black, which is exactly "fades
// into the background black screen." Increased rotation variety per
// shard for a more irregular, glass-like break instead of a uniform
// grid dissolving.

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
    // impact-ish origin near the bottom-right (roughly where the dog
    // sits after a completed swipe-confirm) purely for the stagger
    // timing - shards do NOT travel toward this point, they just start
    // cracking away from it first, like a break propagating outward.
    final origin = Offset(size.width * 0.85, size.height * 0.9);
    final corners = [
      const Offset(0, 0),
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ];
    final maxDist =
        corners.map((c) => (c - origin).distance).reduce(math.max);

    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        final fr = r / (_rows - 1);
        final bg = Color.lerp(_bg1, _bg2, fr)!;
        final left = c * w;
        final top = r * h;
        final restCenter = Offset(left + w / 2, top + h / 2);

        final dist = (restCenter - origin).distance;
        final delay = (dist / maxDist) * 0.35;
        var local = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
        local = Curves.easeOut.transform(local);
        if (local >= 1) continue;

        // each shard falls from its OWN rest position - not toward a
        // shared point. A little per-shard randomness plus a gentle
        // leftward/upward drift bias (loosely "back toward the phone"
        // without literally converging there) reads as glass falling
        // away, not a coordinated warp/zoom.
        final jitterX = ((c * 7 + r * 13) % 17 - 8) * 3.0;
        final jitterY = ((c * 11 + r * 5) % 13 - 6) * 3.0;
        final outX = (-30 + jitterX) * local;
        final outY = (110 + jitterY) * local;
        final scale = 1 - 0.85 * local;
        // fade in the back half only - stays solid through the actual
        // "break" and fades as it recedes, revealing the black layer
        // underneath, not translucent from the very first frame.
        final alpha = local < 0.45 ? 1.0 : 1 - (local - 0.45) / 0.55;
        if (scale <= 0.03 || alpha <= 0.02) continue;
        final rot = ((c * 53 + r * 17) % 40 - 20) * 0.045;

        canvas.save();
        canvas.translate(
            restCenter.dx + outX, restCenter.dy + outY);
        canvas.rotate(rot * local);
        canvas.scale(scale);
        canvas.translate(-w / 2, -h / 2);
        canvas.drawRect(
          Rect.fromLTWH(0, 0, w + 1, h + 1),
          Paint()..color = bg.withValues(alpha: alpha),
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ShatterPainter oldDelegate) =>
      oldDelegate.t != t;
}
