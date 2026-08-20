// widgets/progress_dog.dart
//
// Vector transcription of progress_dog.svg - the draggable dog. Same
// technique as progress_person.dart: hand-rolled CustomPainter, no
// flutter_svg dependency. shape-rendering="crispEdges" in the source ->
// isAntiAlias: false here, matching the pixel-art look.
//
// The file's own declared viewBox height is 132, but its real content
// (the legs) reaches y=144 - not something to "fix" in the source, so
// contentHeight (144) is used for sizing/scaling here instead of the
// viewBox value, to avoid clipping the legs.

import 'package:flutter/material.dart';

class DogFigure extends StatelessWidget {
  final double height;
  const DogFigure({super.key, required this.height});

  static const sourceWidth = 252.0;
  static const contentHeight = 144.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: height * sourceWidth / contentHeight,
      child: const CustomPaint(painter: _DogPainter(), size: Size.infinite),
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

class _DogPainter extends CustomPainter {
  const _DogPainter();

  // Transcribed 1:1 from progress_dog.svg's <rect> elements.
  static const _rects = <_Rect>[
    _Rect(24, 60, 156, 12, 0xFF08221d),
    _Rect(24, 72, 156, 24, 0xFF2dd4bf),
    _Rect(24, 96, 156, 12, 0xFF08221d),
    _Rect(0, 72, 12, 12, 0xFF08221d),
    _Rect(0, 84, 12, 12, 0xFF2dd4bf),
    _Rect(168, 24, 48, 12, 0xFF08221d),
    _Rect(156, 36, 12, 36, 0xFF08221d),
    _Rect(168, 36, 36, 36, 0xFF2dd4bf),
    _Rect(204, 48, 24, 12, 0xFF2dd4bf),
    _Rect(204, 36, 24, 12, 0xFF08221d),
    _Rect(228, 48, 12, 12, 0xFF08221d),
    _Rect(192, 36, 12, 12, 0xFFeafffb),
    _Rect(168, 12, 24, 12, 0xFF08221d),
    _Rect(156, 60, 12, 12, 0xFFef4444),
    _Rect(144, 108, 12, 36, 0xFF0e4a44),
    _Rect(120, 108, 12, 36, 0xFF0e4a44),
    _Rect(96, 108, 12, 36, 0xFF0e4a44),
    _Rect(72, 108, 12, 36, 0xFF0e4a44),
  ];

  // Transcribed 1:1 from the SVG's 3 <polyline> chevrons (the ">>>"
  // drag-direction cue).
  static const _chevrons = <_Chevron>[
    _Chevron(
        [Offset(78.9, 77.0), Offset(92.9, 84.0), Offset(78.9, 91.0)], 0.3),
    _Chevron(
        [Offset(95.0, 77.0), Offset(109.0, 84.0), Offset(95.0, 91.0)], 0.6),
    _Chevron(
        [Offset(111.1, 77.0), Offset(125.1, 84.0), Offset(111.1, 91.0)], 1.0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.height / DogFigure.contentHeight;
    canvas.scale(scale);
    for (final r in _rects) {
      canvas.drawRect(
        Rect.fromLTWH(r.x, r.y, r.w, r.h),
        Paint()
          ..color = Color(r.color)
          ..isAntiAlias = false,
      );
    }
    for (final c in _chevrons) {
      canvas.drawPath(
        Path()..addPolygon(c.points, false),
        Paint()
          ..color = const Color(0xFF00FF41).withValues(alpha: c.opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DogPainter oldDelegate) => false;
}
