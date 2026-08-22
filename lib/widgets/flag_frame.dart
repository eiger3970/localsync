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
// 2026-08-22: rewritten. The original version tiled a flag's stripe
// colours as repeating `thickness`-square blocks around each edge
// independently - looked like bunting/candy-cane, not a flag, and
// couldn't represent crosses, cantons or correct band proportions at
// all. Real feedback: "still just basic blue for Australia... not
// worth paying for" - a solid field with a handful of scattered dots
// doesn't read as a flag either.
//
// The frame this file paints is only `thickness` (8px) wide around
// the screen's outer edge. That's a hard geometric constraint on what
// can ever be shown here, and it drives every decision below:
//
// - An edge-spanning shape - a stripe band, a cross bar that runs the
//   flag's full width or height - genuinely intersects the 8px band
//   everywhere along its length, so it can be drawn as if painting
//   the WHOLE flag at screen scale and then clipping to just the
//   border (see _FlagFramePainter.paint). What's left visible is a
//   correct, real slice of the actual flag - not a simplification.
// - A corner-anchored shape - a canton (US's blue star field, the
//   Union Jack inside Australia/NZ's canton) - touches both edges
//   meeting at that corner, so the same clip-the-whole-flag approach
//   reveals a genuine L-shaped slice of it too.
// - A CENTRED shape that touches no edge at all - Argentina's Sol de
//   Mayo, Brazil's yellow diamond and blue circle, Canada's maple
//   leaf, the Southern Cross constellation itself, the fine star grid
//   inside a canton - can never appear this way. Not "simplified" -
//   literally zero pixels of it would ever fall inside an 8px edge
//   band, at any screen size. Two different responses to that,
//   per-flag (see theme.dart's per-palette comments for which):
//     1. Drop the detail and keep what IS achievable (Argentina's
//        bands, Canada's bands, Brazil/Albania fall back further to
//        a single-colour "flag can't be done here" solid border).
//     2. Where the detail is small and point-like (stars), draw it
//        directly onto the border geometry instead of clipping it
//        from an invisible interior - honestly a stylised placement
//        along the correct side of the flag, not a claim of exact
//        constellation accuracy, but a real star polygon rather than
//        a dot.
//
// FlagKind (theme.dart) selects the treatment; AppPalette carries the
// per-flag data each treatment needs.

import 'dart:math';
import 'package:flutter/material.dart';
import '../theme.dart';

class FlagFrame extends StatelessWidget {
  final Widget child;
  final double thickness;
  const FlagFrame({super.key, required this.child, this.thickness = 8});

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.current;
    if (palette.flagKind == FlagKind.none) return child;
    return CustomPaint(
      painter: _FlagFramePainter(palette: palette, thickness: thickness),
      child: Padding(
        padding: EdgeInsets.all(thickness),
        child: child,
      ),
    );
  }
}

const _ujBlue = Color(0xFF00247D);
const _ujRed = Color(0xFFC8102E);
const _usCantonBlue = Color(0xFF3C3B6E);
const _nzStarRed = Color(0xFFCC142B);

class _FlagFramePainter extends CustomPainter {
  final AppPalette palette;
  final double thickness;
  _FlagFramePainter({required this.palette, required this.thickness});

  @override
  void paint(Canvas canvas, Size size) {
    final inner = Rect.fromLTWH(
      thickness,
      thickness,
      size.width - 2 * thickness,
      size.height - 2 * thickness,
    );
    final framePath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(inner)
      ..fillType = PathFillType.evenOdd;

    canvas.save();
    canvas.clipPath(framePath);
    final full = Rect.fromLTWH(0, 0, size.width, size.height);
    switch (palette.flagKind) {
      case FlagKind.stripes:
        _drawStripes(canvas, size);
        break;
      case FlagKind.nordicCross:
        _drawNordicCross(canvas, size);
        break;
      case FlagKind.stGeorgesCross:
        _drawCenteredCross(canvas, full, field: Colors.white, cross: palette.accent);
        break;
      case FlagKind.unionJack:
        _drawUnionJack(canvas, full);
        break;
      case FlagKind.starsAndStripes:
        _drawStripes(canvas, size);
        _drawUsCanton(canvas, size);
        _paintCantonStars(canvas, size);
        break;
      case FlagKind.southernCross:
        canvas.drawRect(full, Paint()..color = palette.accent);
        // Canton is exactly half the flag's width and height - real
        // Wikimedia Australia SVG (viewBox 0 0 10080 5040, canton
        // clip 0,0-6,3 of a 12x6 box), confirmed 2026-08-22. True of
        // NZ too - same Blue Ensign proportions.
        _drawUnionJack(canvas, Rect.fromLTWH(0, 0, size.width * 0.5, size.height * 0.5));
        _paintSouthernCrossStars(canvas, size);
        break;
      case FlagKind.none:
        break;
    }
    canvas.restore();
  }

  // ── Edge-spanning shapes (drawn at full screen scale, revealed only
  //    through the clip set up in paint()) ──────────────────────────

  void _drawStripes(Canvas canvas, Size size) {
    final colors = palette.flagStripes;
    if (colors == null || colors.isEmpty) return;
    final weights = palette.stripeWeights ?? List<double>.filled(colors.length, 1);
    final totalWeight = weights.fold<double>(0, (a, b) => a + b);
    final vertical = palette.stripesVertical;
    final length = vertical ? size.width : size.height;
    var pos = 0.0;
    for (var i = 0; i < colors.length; i++) {
      final bandLength = length * weights[i] / totalWeight;
      final rect = vertical
          ? Rect.fromLTWH(pos, 0, bandLength, size.height)
          : Rect.fromLTWH(0, pos, size.width, bandLength);
      canvas.drawRect(rect, Paint()..color = colors[i]);
      pos += bandLength;
    }
  }

  // Off-centre cross, bars shifted toward the hoist (left) per Nordic
  // flag proportions - unlike England's centred St George's Cross.
  void _drawNordicCross(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = Colors.white);
    final barThickness = size.shortestSide * 0.16;
    final vertX = size.width * 0.35;
    canvas.drawRect(
      Rect.fromLTWH(vertX - barThickness / 2, 0, barThickness, size.height),
      Paint()..color = palette.accent,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, size.height / 2 - barThickness / 2, size.width, barThickness),
      Paint()..color = palette.accent,
    );
  }

  void _drawCenteredCross(Canvas canvas, Rect rect, {required Color field, required Color cross}) {
    canvas.drawRect(rect, Paint()..color = field);
    final barThickness = rect.shortestSide * 0.2;
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.center.dy - barThickness / 2, rect.width, barThickness),
      Paint()..color = cross,
    );
    canvas.drawRect(
      Rect.fromLTWH(rect.center.dx - barThickness / 2, rect.top, barThickness, rect.height),
      Paint()..color = cross,
    );
  }

  // Diagonal saltire + upright cross within an arbitrary rect - reused
  // both for the UK's full-bleed flag and, at a smaller scale, for the
  // Union Jack canton inside Australia/NZ's Southern Cross flags. Not
  // official proportions, but a real diagonal-cross-on-blue pattern,
  // not a plain solid field.
  void _drawUnionJack(Canvas canvas, Rect rect) {
    canvas.drawRect(rect, Paint()..color = _ujBlue);
    final short = rect.shortestSide;

    final whiteDiag = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = short * 0.22;
    canvas.drawLine(rect.topLeft, rect.bottomRight, whiteDiag);
    canvas.drawLine(rect.topRight, rect.bottomLeft, whiteDiag);

    // Thinner, offset red saltire on top - a rough stand-in for the
    // real flag's counter-changed fimbriation.
    final redOffset = short * 0.05;
    final redDiag = Paint()
      ..color = _ujRed
      ..style = PaintingStyle.stroke
      ..strokeWidth = short * 0.09;
    canvas.drawLine(rect.topLeft.translate(0, redOffset), rect.bottomRight.translate(0, redOffset), redDiag);
    canvas.drawLine(rect.topRight.translate(0, redOffset), rect.bottomLeft.translate(0, redOffset), redDiag);

    final whiteCrossWidth = short * 0.34;
    final whiteCross = Paint()..color = Colors.white;
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.center.dy - whiteCrossWidth / 2, rect.width, whiteCrossWidth),
      whiteCross,
    );
    canvas.drawRect(
      Rect.fromLTWH(rect.center.dx - whiteCrossWidth / 2, rect.top, whiteCrossWidth, rect.height),
      whiteCross,
    );

    final redCrossWidth = short * 0.16;
    final redCross = Paint()..color = _ujRed;
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.center.dy - redCrossWidth / 2, rect.width, redCrossWidth),
      redCross,
    );
    canvas.drawRect(
      Rect.fromLTWH(rect.center.dx - redCrossWidth / 2, rect.top, redCrossWidth, rect.height),
      redCross,
    );
  }

  void _drawUsCanton(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width * 0.4, size.height * (7 / 13));
    canvas.drawRect(rect, Paint()..color = _usCantonBlue);
  }

  // ── Point emblems - drawn directly onto the visible border strip,
  //    not clipped from an invisible interior (see file header) ─────

  void _paintCantonStars(Canvas canvas, Size size) {
    final half = thickness / 2;
    final r = thickness * 0.28;
    final cantonW = size.width * 0.4;
    final cantonH = size.height * (7 / 13);
    final positions = <Offset>[
      Offset(cantonW * 0.10, half),
      Offset(cantonW * 0.24, half),
      Offset(cantonW * 0.38, half),
      Offset(half, cantonH * 0.20),
      Offset(half, cantonH * 0.45),
      Offset(half, cantonH * 0.70),
    ];
    for (final p in positions) {
      _drawStar(canvas, p, r, 5, Colors.white);
    }
  }

  void _paintSouthernCrossStars(Canvas canvas, Size size) {
    final starColor = palette.southernCrossRedStars ? _nzStarRed : Colors.white;
    final edgeColor = palette.southernCrossRedStars ? Colors.white : null;
    final r = thickness * 0.38;
    final half = thickness / 2;
    final rightEdgeX = size.width - half;
    final bottomEdgeY = size.height - half;

    // Y/X fractions below mirror the real Australia flag's named star
    // positions (Wikimedia SVG, viewBox 0 0 10080 5040, confirmed
    // 2026-08-22): gamma (75%,17%), delta (86%,37%), alpha
    // (75%,83%), beta (62.5%,44%), epsilon small (80%,54%) - snapped
    // onto whichever visible edge (right or bottom) each real
    // position is closest to, since none of them touch an actual
    // flag edge and an 8px frame can only ever show what's drawn
    // there (see file header). NZ has no sourced SVG yet, so its
    // Southern Cross (4 stars, no epsilon) reuses these same
    // positions as an approximation until one is provided.
    final positions = <Offset>[
      Offset(rightEdgeX, size.height * 0.17), // gamma
      Offset(rightEdgeX, size.height * 0.37), // delta
      Offset(size.width * 0.75, bottomEdgeY), // alpha
      Offset(rightEdgeX, size.height * 0.44), // beta
      Offset(size.width * 0.80, bottomEdgeY), // epsilon (small)
    ];
    final count = (palette.starCount ?? positions.length).clamp(0, positions.length);
    for (var i = 0; i < count; i++) {
      final small = i == 4;
      _drawStar(canvas, positions[i], small ? r * 0.6 : r, small ? 5 : 7, starColor, edgeColor: edgeColor);
    }

    if (palette.southernCrossCommonwealthStar) {
      // Real position (25%, 75%) - x snapped to the left edge since
      // the canton anchors it there; y matches the real fraction.
      _drawStar(canvas, Offset(half, size.height * 0.75), r * 0.85, 7, starColor, edgeColor: edgeColor);
    }
  }

  void _drawStar(Canvas canvas, Offset center, double outerRadius, int points, Color color, {Color? edgeColor}) {
    if (edgeColor != null) {
      canvas.drawPath(_starPath(center, outerRadius * 1.3, points), Paint()..color = edgeColor);
    }
    canvas.drawPath(_starPath(center, outerRadius, points), Paint()..color = color);
  }

  Path _starPath(Offset center, double outerRadius, int points, {double innerRatio = 0.45}) {
    final innerRadius = outerRadius * innerRatio;
    final path = Path();
    final step = pi / points;
    for (var i = 0; i < points * 2; i++) {
      final r = i.isEven ? outerRadius : innerRadius;
      final angle = -pi / 2 + i * step;
      final x = center.dx + r * cos(angle);
      final y = center.dy + r * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _FlagFramePainter oldDelegate) =>
      oldDelegate.palette != palette || oldDelegate.thickness != thickness;
}
