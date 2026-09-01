// widgets/shatter_page_route.dart
//
// The transition for the one moment the welcome flow's pastel world
// actually meets the real app's dark one. Used for the one
// welcome->real-app handoff (the preview screens' SwapGifSwipeConfirm
// into LinkingScreen), not a general-purpose route - keep it there.
//
// [revisions 1-8 covered a glass-shatter concept, then a falling-tile
// grid with a diagonal wave sweep and fade-out - through many rounds
// without landing. See git history if that log is ever needed.]
//
// 2026-09-01, ninth revision: "fade into background, not swipe around
// the screen like currently." The diagonal wave sweep across the tile
// grid read as motion travelling across the screen, not a clean
// handoff. Dropped the tile grid entirely for a plain fade to black -
// no grid, no wave, no per-tile timing, just opacity.

import 'package:flutter/material.dart';

class ShatterPageRoute<T> extends PageRouteBuilder<T> {
  ShatterPageRoute({required WidgetBuilder builder})
      : super(
          transitionDuration: const Duration(milliseconds: 900),
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
                      // what's revealed as this fades away is clean
                      // black, never the real page's own UI
                      return Opacity(
                        opacity: 1 - Curves.easeIn.transform(t),
                        child: Container(color: Colors.black),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
}
