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

import 'dart:math' as math;
import 'package:flutter/material.dart';

class ShatterPageRoute<T> extends PageRouteBuilder<T> {
  ShatterPageRoute({required WidgetBuilder builder})
      : super(
          transitionDuration: const Duration(milliseconds: 1200),
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

const _cols = 7;
const _rows = 12;

class _GlassSmashPainter extends CustomPainter {
  final double t;
  _GlassSmashPainter(this.t);

  static const _bg1 = Color(0xFFF3FBFA);
  static const _bg2 = Color(0xFFE1F5F0);

  // Fixed seed - same per-tile stagger every frame of the same
  // transition, not a new random layout each repaint. One shared
  // Random instance across the whole list - a fresh Random(7) per
  // element would reseed identically each time and produce the same
  // value for every tile. Tight 0-0.15 spread (not 0-0.6) - an impact
  // moment, most pieces start together, not a slow drip.
  static final _delays = () {
    final rand = math.Random(7);
    return List.generate(_cols * _rows, (_) => rand.nextDouble() * 0.15);
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width / _cols;
    final h = size.height / _rows;

    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        final i = r * _cols + c;
        final fr = r / (_rows - 1);
        final bg = Color.lerp(_bg1, _bg2, fr)!;

        final delay = _delays[i];
        var local = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
        local = Curves.easeIn.transform(local);
        if (local <= 0) continue;

        final alpha = 1 - local;
        if (alpha <= 0.02) continue;

        // 2026-09-01, eleventh revision: "falls to bottom of screen,
        // but should fall getting smaller into the distance, not up,
        // down, left or right." No positional movement at all now -
        // each piece shrinks toward its own center in place. Scale is
        // the only depth cue; nothing travels anywhere on screen.
        final scale = 1.0 - 0.7 * local;
        final cx = c * w + w / 2;
        final cy = r * h + h / 2;
        final tw = (w + 1) * scale;
        final th = (h + 1) * scale;

        canvas.drawRect(
          Rect.fromCenter(center: Offset(cx, cy), width: tw, height: th),
          Paint()..color = bg.withValues(alpha: alpha),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GlassSmashPainter oldDelegate) =>
      oldDelegate.t != t;
}
