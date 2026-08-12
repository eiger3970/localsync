// widgets/progress_person.dart
//
// Vector transcription of progress_person.svg - the fixed figure
// holding the leash. Same technique as progress_dog.dart: hand-rolled
// CustomPainter, no flutter_svg dependency, pixel-crisp at any size.
// This widget never animates and never becomes a gif - see
// leash_swipe_confirm.dart's header comment for why.

import 'package:flutter/material.dart';

class PersonFigure extends StatelessWidget {
  final double height;
  const PersonFigure({super.key, required this.height});

  static const sourceWidth = 90.0;
  static const sourceHeight = 140.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: height * sourceWidth / sourceHeight,
      child: const CustomPaint(painter: _PersonPainter(), size: Size.infinite),
    );
  }
}

class _Rect {
  final double x, y, w, h;
  final int color;
  const _Rect(this.x, this.y, this.w, this.h, this.color);
}

class _PersonPainter extends CustomPainter {
  const _PersonPainter();

  // Transcribed 1:1 from progress_person.svg's <rect> elements.
  static const _rects = <_Rect>[
    _Rect(29.4, 2.0, 31.2, 31.2, 0xFF2dd4bf),
    _Rect(37.2, 12.4, 7.8, 7.8, 0xFF08221d),
    _Rect(24.2, 35.8, 41.6, 46.8, 0xFF2dd4bf),
    _Rect(65.8, 54.0, 20.8, 15.6, 0xFF2dd4bf),
    _Rect(8.6, 48.8, 15.6, 15.6, 0xFF0e4a44),
    _Rect(29.4, 85.2, 13.0, 41.6, 0xFF0e4a44),
    _Rect(47.6, 85.2, 13.0, 41.6, 0xFF0e4a44),
    _Rect(26.8, 124.2, 18.2, 7.8, 0xFF08221d),
    _Rect(45.0, 124.2, 18.2, 7.8, 0xFF08221d),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.height / PersonFigure.sourceHeight;
    canvas.scale(scale);
    for (final r in _rects) {
      canvas.drawRect(
        Rect.fromLTWH(r.x, r.y, r.w, r.h),
        Paint()
          ..color = Color(r.color)
          ..isAntiAlias = false,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PersonPainter oldDelegate) => false;
}
