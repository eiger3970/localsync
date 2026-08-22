// widgets/flag_paint.dart
//
// 2026-08-22: shared Canvas primitives, extracted out of
// flag_frame.dart's border painter so flag_backdrop.dart's tiled
// mini-flags can reuse the exact same Union Jack/star drawing instead
// of a second hand-copied version drifting out of sync with it.

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

// 2026-08-22: "Australia and UK union jacks are wrong... use the svgs
// I provided" - real feedback. The border previously always used
// drawUnionJack's hand-drawn approximation even for countries with a
// real sourced SVG, on the reasoning that an 8px clip shows so little
// that fidelity wouldn't matter - true for simple axis-aligned bands
// (stripes/crosses), false here: a Union Jack canton concentrates
// diagonal/cross detail right at the corner the border actually
// shows, so the hand-drawn approximation's inaccuracy is genuinely
// visible there. flag_frame.dart now loads and draws this real
// picture, scaled, for FlagKind.unionJack and southernCross wherever
// palette.flagAsset is set.
Future<PictureInfo> loadFlagSvgPicture(String assetPath) => vg.loadPicture(SvgAssetLoader(assetPath), null);

// Draws a loaded SVG picture scaled (not cropped) to exactly fill
// [rect] - same "resize to fit" approach flag_backdrop.dart's tiles
// already use, applied here to the border.
void drawPictureScaled(Canvas canvas, PictureInfo info, Rect rect) {
  canvas.save();
  canvas.translate(rect.left, rect.top);
  canvas.scale(rect.width / info.size.width, rect.height / info.size.height);
  canvas.drawPicture(info.picture);
  canvas.restore();
}

const ujBlue = Color(0xFF00247D);
const ujRed = Color(0xFFC8102E);
const nzStarRed = Color(0xFFCC142B);
// 2026-08-22: real official value (#0A3161) per user-sourced Wikimedia
// SVG (assets/flags/us.svg) - was 0xFF3C3B6E, a real colour error, not
// a simplification.
const usCantonBlue = Color(0xFF0A3161);

// 2026-08-22: extracted from flag_frame.dart's border painter so
// flag_backdrop.dart's mini-flag tiles can draw the exact same
// stripes/crosses at a small, unclipped scale - same shapes, just
// invoked against a small Rect instead of the full screen.

void drawStripes(Canvas canvas, Rect rect, List<Color> colors, {bool vertical = false, List<double>? weights}) {
  if (colors.isEmpty) return;
  final w = weights ?? List<double>.filled(colors.length, 1);
  final totalWeight = w.fold<double>(0, (a, b) => a + b);
  final length = vertical ? rect.width : rect.height;
  var pos = vertical ? rect.left : rect.top;
  for (var i = 0; i < colors.length; i++) {
    final bandLength = length * w[i] / totalWeight;
    final bandRect = vertical
        ? Rect.fromLTWH(pos, rect.top, bandLength, rect.height)
        : Rect.fromLTWH(rect.left, pos, rect.width, bandLength);
    canvas.drawRect(bandRect, Paint()..color = colors[i]);
    pos += bandLength;
  }
}

// Off-centre cross, bars shifted toward the hoist (left) per Nordic
// flag proportions - unlike drawCenteredCross's centred bars.
void drawNordicCross(Canvas canvas, Rect rect, {required Color field, required Color cross}) {
  canvas.drawRect(rect, Paint()..color = field);
  final barThickness = rect.shortestSide * 0.16;
  final vertX = rect.left + rect.width * 0.35;
  canvas.drawRect(
    Rect.fromLTWH(vertX - barThickness / 2, rect.top, barThickness, rect.height),
    Paint()..color = cross,
  );
  canvas.drawRect(
    Rect.fromLTWH(rect.left, rect.center.dy - barThickness / 2, rect.width, barThickness),
    Paint()..color = cross,
  );
}

void drawCenteredCross(Canvas canvas, Rect rect, {required Color field, required Color cross}) {
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

// Diagonal saltire + upright cross within an arbitrary rect - used for
// the UK's full-bleed flag, the canton inside Australia/NZ's Southern
// Cross flags, and (at a much smaller scale) each tile of the bold
// backdrop's repeating mini-flags. Not official proportions, but a
// real diagonal-cross-on-blue pattern, not a plain solid field.
void drawUnionJack(Canvas canvas, Rect rect) {
  canvas.drawRect(rect, Paint()..color = ujBlue);
  final short = rect.shortestSide;

  final whiteDiag = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = short * 0.22;
  canvas.drawLine(rect.topLeft, rect.bottomRight, whiteDiag);
  canvas.drawLine(rect.topRight, rect.bottomLeft, whiteDiag);

  // Thinner, offset red saltire on top - a rough stand-in for the real
  // flag's counter-changed fimbriation.
  final redOffset = short * 0.05;
  final redDiag = Paint()
    ..color = ujRed
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
  final redCross = Paint()..color = ujRed;
  canvas.drawRect(
    Rect.fromLTWH(rect.left, rect.center.dy - redCrossWidth / 2, rect.width, redCrossWidth),
    redCross,
  );
  canvas.drawRect(
    Rect.fromLTWH(rect.center.dx - redCrossWidth / 2, rect.top, redCrossWidth, rect.height),
    redCross,
  );
}

void drawStar(Canvas canvas, Offset center, double outerRadius, int points, Color color, {Color? edgeColor}) {
  if (edgeColor != null) {
    canvas.drawPath(starPath(center, outerRadius * 1.3, points), Paint()..color = edgeColor);
  }
  canvas.drawPath(starPath(center, outerRadius, points), Paint()..color = color);
}

Path starPath(Offset center, double outerRadius, int points, {double innerRatio = 0.45}) {
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
