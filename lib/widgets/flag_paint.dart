// widgets/flag_paint.dart
//
// 2026-08-22: shared Canvas primitives, extracted out of
// flag_frame.dart's border painter so flag_backdrop.dart's tiled
// mini-flags can reuse the exact same Union Jack/star drawing instead
// of a second hand-copied version drifting out of sync with it.

import 'dart:math';
import 'package:flutter/material.dart';

const ujBlue = Color(0xFF00247D);
const ujRed = Color(0xFFC8102E);
const nzStarRed = Color(0xFFCC142B);

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
