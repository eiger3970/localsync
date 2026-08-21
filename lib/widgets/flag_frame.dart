// widgets/flag_frame.dart
//
// 2026-08-21: "add real flags around, like a mad patriot football fan,
// like a Fortnite skin around the edges, but so you can still see and
// operate the functions." A thin repeating-stripe border painted
// around the screen's outer edge - the functional content sits
// inside, fully clear, never covered by the frame.
//
// Deliberately code-drawn (CustomPainter), not a hand-authored SVG
// asset - this app has real prior history with custom SVGs breaking
// invisibly with no way to preview before a sideload (the pairing
// screen's key/lock took several iterations to get right). A
// code-drawn frame's shape logic can be verified directly instead of
// guessed at.
//
// Only palettes with a genuinely stripe-based flag get a frame at all
// (theme.dart's AppPalette.flagStripes) - complex flags (Union Jack,
// stars-and-stripes, Southern Cross) are left null rather than drawn
// as a misleading simplified pattern, so this widget passes its child
// straight through unchanged for those.

import 'package:flutter/material.dart';
import '../theme.dart';

class FlagFrame extends StatelessWidget {
  final Widget child;
  final double thickness;
  const FlagFrame({super.key, required this.child, this.thickness = 8});

  @override
  Widget build(BuildContext context) {
    final stripes = AppTheme.current.flagStripes;
    if (stripes == null || stripes.isEmpty) return child;
    return CustomPaint(
      painter: _FlagFramePainter(stripes: stripes, thickness: thickness),
      child: Padding(
        padding: EdgeInsets.all(thickness),
        child: child,
      ),
    );
  }
}

class _FlagFramePainter extends CustomPainter {
  final List<Color> stripes;
  final double thickness;
  _FlagFramePainter({required this.stripes, required this.thickness});

  @override
  void paint(Canvas canvas, Size size) {
    final bandLength = thickness;
    _paintStrip(canvas, Rect.fromLTWH(0, 0, size.width, thickness),
        horizontal: true, bandLength: bandLength);
    _paintStrip(
        canvas,
        Rect.fromLTWH(
            0, size.height - thickness, size.width, thickness),
        horizontal: true,
        bandLength: bandLength);
    _paintStrip(canvas, Rect.fromLTWH(0, 0, thickness, size.height),
        horizontal: false, bandLength: bandLength);
    _paintStrip(
        canvas,
        Rect.fromLTWH(
            size.width - thickness, 0, thickness, size.height),
        horizontal: false,
        bandLength: bandLength);
  }

  // Fills one edge strip with repeating bands cycling through
  // [stripes], oriented perpendicular to the strip's own length - a
  // top/bottom strip's bands run left-to-right, a left/right strip's
  // bands run top-to-bottom. Same repeating sequence on all 4 edges,
  // giving a continuous frame around the whole perimeter.
  void _paintStrip(Canvas canvas, Rect rect,
      {required bool horizontal, required double bandLength}) {
    final length = horizontal ? rect.width : rect.height;
    var pos = 0.0;
    var i = 0;
    while (pos < length) {
      final segment = (pos + bandLength > length) ? length - pos : bandLength;
      final paint = Paint()..color = stripes[i % stripes.length];
      final bandRect = horizontal
          ? Rect.fromLTWH(rect.left + pos, rect.top, segment, rect.height)
          : Rect.fromLTWH(rect.left, rect.top + pos, rect.width, segment);
      canvas.drawRect(bandRect, paint);
      pos += bandLength;
      i++;
    }
  }

  @override
  bool shouldRepaint(covariant _FlagFramePainter oldDelegate) =>
      oldDelegate.stripes != stripes || oldDelegate.thickness != thickness;
}
