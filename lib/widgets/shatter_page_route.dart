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
// fades... keep the white breaking up into pieces that fade into black
// background" - a single full-screen opacity read as an abrupt flash,
// and the piece-by-piece breakup (the actual thing liked) was lost
// along with the wave. Tenth revision: tile grid is back, but each
// tile now only fades in place (no y-offset/fall) with a per-tile
// RANDOM stagger (fixed seed, so it's deterministic frame to frame) -
// pieces dissolve independently instead of a directional sweep, and
// nothing pops as one hard full-screen flash.

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
                          // what's revealed as pieces fade away is
                          // clean black, never the real page's own UI
                          Container(color: Colors.black),
                          CustomPaint(
                            size: Size.infinite,
                            painter: _PieceDissolvePainter(t),
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

class _PieceDissolvePainter extends CustomPainter {
  final double t;
  _PieceDissolvePainter(this.t);

  static const _bg1 = Color(0xFFF3FBFA);
  static const _bg2 = Color(0xFFE1F5F0);

  // Fixed seed - same per-tile stagger every frame of the same
  // transition, not a new random layout each repaint. One shared
  // Random instance across the whole list - a fresh Random(7) per
  // element would reseed identically each time and produce the same
  // value for every tile.
  static final _delays = () {
    final rand = math.Random(7);
    return List.generate(_cols * _rows, (_) => rand.nextDouble() * 0.6);
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
        final alpha = 1 - local;
        if (alpha <= 0.02) continue;

        canvas.drawRect(
          Rect.fromLTWH(c * w, r * h, w + 1, h + 1),
          Paint()..color = bg.withValues(alpha: alpha),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PieceDissolvePainter oldDelegate) =>
      oldDelegate.t != t;
}
