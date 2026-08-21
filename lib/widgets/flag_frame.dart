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
// Two flag treatments, per theme.dart's AppPalette fields:
// - flagStripes: genuinely stripe-based flags (Germany, France, etc.)
// - starCount: star-based flags (Australia, US, NZ) - "still just
//   basic blue for Australia... not worth paying for" (2026-08-21,
//   real feedback) was a solid-accent border with no stars at all;
//   this draws small dots scattered across it instead, a real if
//   simplified visual difference.
// Palettes with neither (complex flags like the UK's Union Jack, or
// the 3 non-flag skins) pass the child through unchanged.

import 'package:flutter/material.dart';
import '../theme.dart';

class FlagFrame extends StatelessWidget {
  final Widget child;
  final double thickness;
  const FlagFrame({super.key, required this.child, this.thickness = 8});

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.current;
    final stripes = palette.flagStripes;
    final stars = palette.starCount;
    if ((stripes == null || stripes.isEmpty) && (stars == null || stars < 1)) {
      return child;
    }
    return CustomPaint(
      painter: _FlagFramePainter(
        stripes: stripes,
        accent: palette.accent,
        starColor: palette.star,
        starCount: stars,
        thickness: thickness,
      ),
      child: Padding(
        padding: EdgeInsets.all(thickness),
        child: child,
      ),
    );
  }
}

class _FlagFramePainter extends CustomPainter {
  final List<Color>? stripes;
  final Color accent;
  final Color starColor;
  final int? starCount;
  final double thickness;
  _FlagFramePainter({
    required this.stripes,
    required this.accent,
    required this.starColor,
    required this.starCount,
    required this.thickness,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final edges = [
      Rect.fromLTWH(0, 0, size.width, thickness), // top
      Rect.fromLTWH(0, size.height - thickness, size.width, thickness), // bottom
      Rect.fromLTWH(0, 0, thickness, size.height), // left
      Rect.fromLTWH(size.width - thickness, 0, thickness, size.height), // right
    ];

    final stripeColors = stripes;
    if (stripeColors != null && stripeColors.isNotEmpty) {
      for (final edge in edges) {
        _paintStripedEdge(canvas, edge, stripeColors);
      }
      return;
    }

    // Star treatment: solid accent field, small dots scattered around
    // the perimeter - not an accurate canton/constellation layout, a
    // real visual difference from a plain solid border rather than a
    // full flag reproduction.
    final fieldPaint = Paint()..color = accent;
    for (final edge in edges) {
      canvas.drawRect(edge, fieldPaint);
    }
    final count = starCount ?? 0;
    if (count < 1) return;
    final dotPaint = Paint()..color = starColor;
    final perimeter = 2 * (size.width + size.height - 2 * thickness);
    final spacing = perimeter / count;
    var travelled = spacing / 2;
    for (var i = 0; i < count; i++) {
      final point = _pointAlongPerimeter(size, travelled);
      canvas.drawCircle(point, thickness * 0.22, dotPaint);
      travelled += spacing;
    }
  }

  // Walks [distance] along the inner perimeter of the frame (centered
  // in the border band), starting from the top-left corner, clockwise.
  Offset _pointAlongPerimeter(Size size, double distance) {
    final half = thickness / 2;
    final w = size.width - thickness;
    final h = size.height - thickness;
    var d = distance % (2 * (w + h));
    if (d < w) return Offset(half + d, half);
    d -= w;
    if (d < h) return Offset(size.width - half, half + d);
    d -= h;
    if (d < w) return Offset(size.width - half - d, size.height - half);
    d -= w;
    return Offset(half, size.height - half - d);
  }

  // Fills one edge strip with repeating bands cycling through
  // [stripeColors], oriented perpendicular to the strip's own length -
  // a top/bottom strip's bands run left-to-right, a left/right strip's
  // bands run top-to-bottom. Same repeating sequence on all 4 edges,
  // giving a continuous frame around the whole perimeter.
  void _paintStripedEdge(Canvas canvas, Rect rect, List<Color> stripeColors) {
    final horizontal = rect.width >= rect.height;
    final bandLength = thickness;
    final length = horizontal ? rect.width : rect.height;
    var pos = 0.0;
    var i = 0;
    while (pos < length) {
      final segment = (pos + bandLength > length) ? length - pos : bandLength;
      final paint = Paint()..color = stripeColors[i % stripeColors.length];
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
      oldDelegate.stripes != stripes ||
      oldDelegate.accent != accent ||
      oldDelegate.starColor != starColor ||
      oldDelegate.starCount != starCount ||
      oldDelegate.thickness != thickness;
}
