// widgets/shatter_page_route.dart
//
// 2026-08-31: the transition for the one moment the welcome flow's
// pastel world actually meets the real app's dark one. Used for the
// one welcome->real-app handoff (the preview screens'
// SwapGifSwipeConfirm into LinkingScreen), not a general-purpose
// route - keep it there.
//
// [revisions 1-7 covered a glass-shatter concept - uniform grid, then
// an irregular radial crack pattern with an impact flash and edge
// highlights - through many rounds without landing. See git history if
// that log is ever needed.]
//
// 2026-08-31, eighth revision, direct redirect: "change from shattering
// glass as the effect is too complicated... try tiles falling back into
// the dark screen, perhaps The Guardian newspaper tiles." Dropped glass
// entirely for something deliberately simpler and more reliable: a
// plain grid of rectangular tiles, falling straight down under gravity
// (accelerating, not decelerating - a drop, not an impact), staggered
// in a diagonal wave sweeping from the top-left corner - the classic
// newspaper/kiosk tile-reveal pattern. No crack physics, no perspective
// math, no per-tile flourishes - simple was the explicit ask this time.

import 'package:flutter/material.dart';

class ShatterPageRoute<T> extends PageRouteBuilder<T> {
  ShatterPageRoute({required WidgetBuilder builder})
      : super(
          transitionDuration: const Duration(milliseconds: 1400),
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
                          // what's revealed as tiles fall away is clean
                          // black, never the real page's own UI
                          Container(color: Colors.black),
                          CustomPaint(
                            size: Size.infinite,
                            painter: _TilePainter(t),
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

class _TilePainter extends CustomPainter {
  final double t;
  _TilePainter(this.t);

  static const _bg1 = Color(0xFFF3FBFA);
  static const _bg2 = Color(0xFFE1F5F0);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width / _cols;
    final h = size.height / _rows;
    final maxWave = (_cols - 1) + (_rows - 1);

    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        final fr = r / (_rows - 1);
        final bg = Color.lerp(_bg1, _bg2, fr)!;

        // diagonal wave from the top-left - each tile's turn to fall
        // starts a little later than the one above/left of it
        final wave = (c + r) / maxWave;
        final delay = wave * 0.5;
        var local = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
        // a drop accelerates - easeIn, not easeOut (that was for a
        // sudden impact, this is a release)
        local = Curves.easeIn.transform(local);
        if (local <= 0) continue;

        final left = c * w;
        final top = r * h;
        final fallY = size.height * 0.9 * local;
        final alpha = local < 0.7 ? 1.0 : 1 - (local - 0.7) / 0.3;
        if (alpha <= 0.02) continue;

        canvas.drawRect(
          Rect.fromLTWH(left, top + fallY, w + 1, h + 1),
          Paint()..color = bg.withValues(alpha: alpha),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TilePainter oldDelegate) =>
      oldDelegate.t != t;
}
