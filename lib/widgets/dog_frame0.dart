// widgets/dog_frame0.dart
//
// 2026-08-19: renders the resting-pose dog-on-leash art directly from
// its source vector data (dog_progress_frame0.svg) instead of the
// pre-rasterized PNG that stood in for it. Hand-rolled rather than
// adding flutter_svg (still avoiding a native-dependency package for a
// cosmetic asset, per this app's earlier build-cost decision - see
// swap_gif_trigger.dart's header) - the source file is genuinely just
// <rect> and 3 <polyline> primitives with shape-rendering="crispEdges",
// no paths/gradients/text, so it's a direct 1:1 transcription of the
// SVG's own draw calls. Values below are copied verbatim from the SVG,
// not approximated. Unlike the PNG (a fixed 396x156 raster, nearest-
// neighbor scaled down for display), this stays pixel-crisp at any
// on-screen size since it's drawn as real rectangles, not resampled.

import 'package:flutter/material.dart';

class DogFrame0 extends StatelessWidget {
  final double height;
  const DogFrame0({super.key, required this.height});

  static const sourceWidth = 396.0;
  static const sourceHeight = 156.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: height * sourceWidth / sourceHeight,
      child: const CustomPaint(painter: _DogFrame0Painter(), size: Size.infinite),
    );
  }
}

class _Rect {
  final double x, y, w, h;
  final int color;
  const _Rect(this.x, this.y, this.w, this.h, this.color);
}

class _Chevron {
  final List<Offset> points;
  final double opacity;
  const _Chevron(this.points, this.opacity);
}

class _DogFrame0Painter extends CustomPainter {
  const _DogFrame0Painter();

  // Transcribed 1:1 from dog_progress_frame0.svg's <rect> elements.
  static const _rects = <_Rect>[
    _Rect(53.4, 26.0, 31.2, 31.2, 0xFF2dd4bf),
    _Rect(61.2, 36.4, 7.8, 7.8, 0xFF08221d),
    _Rect(48.2, 59.8, 41.6, 46.8, 0xFF2dd4bf),
    _Rect(89.8, 78.0, 20.8, 15.6, 0xFF2dd4bf),
    _Rect(32.6, 72.8, 15.6, 15.6, 0xFF0e4a44),
    _Rect(53.4, 109.2, 13.0, 41.6, 0xFF0e4a44),
    _Rect(71.6, 109.2, 13.0, 41.6, 0xFF0e4a44),
    _Rect(50.8, 148.2, 18.2, 7.8, 0xFF08221d),
    _Rect(69.0, 148.2, 18.2, 7.8, 0xFF08221d),
    _Rect(156, 60, 156, 12, 0xFF08221d),
    _Rect(156, 72, 156, 24, 0xFF2dd4bf),
    _Rect(156, 96, 156, 12, 0xFF08221d),
    _Rect(132, 72, 12, 12, 0xFF08221d),
    _Rect(132, 84, 12, 12, 0xFF2dd4bf),
    _Rect(300, 24, 48, 12, 0xFF08221d),
    _Rect(288, 36, 12, 36, 0xFF08221d),
    _Rect(300, 36, 36, 36, 0xFF2dd4bf),
    _Rect(336, 48, 24, 12, 0xFF2dd4bf),
    _Rect(336, 36, 24, 12, 0xFF08221d),
    _Rect(360, 48, 12, 12, 0xFF08221d),
    _Rect(324, 36, 12, 12, 0xFFeafffb),
    _Rect(300, 12, 24, 12, 0xFF08221d),
    _Rect(288, 60, 12, 12, 0xFFef4444),
    _Rect(276, 108, 12, 36, 0xFF0e4a44),
    _Rect(252, 108, 12, 36, 0xFF0e4a44),
    _Rect(228, 108, 12, 36, 0xFF0e4a44),
    _Rect(204, 108, 12, 36, 0xFF0e4a44),
    _Rect(90, 62, 198, 10, 0xFFc8c8cd),
  ];

  // Transcribed 1:1 from the SVG's 3 <polyline> chevrons (the ">>>"
  // swipe-direction cue on the dog's leash/body), fading in left-to-
  // right via their own opacity values.
  static const _chevrons = <_Chevron>[
    _Chevron(
        [Offset(210.9, 77.0), Offset(224.9, 84.0), Offset(210.9, 91.0)], 0.3),
    _Chevron(
        [Offset(227.0, 77.0), Offset(241.0, 84.0), Offset(227.0, 91.0)], 0.6),
    _Chevron(
        [Offset(243.1, 77.0), Offset(257.1, 84.0), Offset(243.1, 91.0)], 1.0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.height / DogFrame0.sourceHeight;
    canvas.scale(scale);

    for (final r in _rects) {
      canvas.drawRect(
        Rect.fromLTWH(r.x, r.y, r.w, r.h),
        Paint()
          ..color = Color(r.color)
          ..isAntiAlias = false, // crispEdges, matches the source SVG
      );
    }

    for (final c in _chevrons) {
      canvas.drawPath(
        Path()..addPolygon(c.points, false),
        Paint()
          ..color = const Color(0xFF00FF41).withOpacity(c.opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DogFrame0Painter oldDelegate) => false;
}
