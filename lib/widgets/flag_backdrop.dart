// widgets/flag_backdrop.dart
//
// 2026-08-22: "2nd option for crazy patriotic with flags all over the
// place where the black space is, of course not hiding app functions."
// flag_frame.dart's border only ever decorates the outer 8px edge -
// this is the louder second treatment: small complete flag icons
// tiled across the app's void background, wherever real content isn't
// already sitting on an opaque kSurface card/list-tile/dialog. Rolled
// out globally via main.dart's MaterialApp.builder (same place
// FlagFrame moved to in this pass), so it - and the border - now
// apply to every screen, not just Home.
//
// Painted BEHIND everything (CustomPaint's `painter`, not
// `foregroundPainter`) and only ever into scaffoldBackgroundColor's
// old territory. Never hides functions: every interactive element
// still sits in its own opaque surface, entirely unaffected by
// whatever's tiled beneath it - this widget never draws on top of
// content, only under it.
//
// Each mini-flag tile is genuinely unclipped (unlike the border), so -
// unlike flag_frame.dart's edge-only approximations - this can use the
// real Southern Cross star coordinates directly (same Wikimedia SVG
// data, see theme.dart's australiaPalette comment).

import 'package:flutter/material.dart';
import '../theme.dart';
import 'flag_paint.dart';

class FlagBackdrop extends StatelessWidget {
  final Widget child;
  const FlagBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.current;
    return CustomPaint(
      painter: _FlagBackdropPainter(palette),
      child: child,
    );
  }
}

class _FlagBackdropPainter extends CustomPainter {
  final AppPalette palette;
  _FlagBackdropPainter(this.palette);

  static const _tileW = 60.0;
  static const _tileH = 30.0;
  static const _gapX = 18.0;
  static const _gapY = 18.0;
  static const _tileOpacity = 0.55;
  static const _tiltRadians = 0.14;

  @override
  void paint(Canvas canvas, Size size) {
    // Same solid void fill every skin already had via
    // scaffoldBackgroundColor - this widget now stands in for that
    // globally (see main.dart), so a non-bold skin looks identical to
    // before.
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = palette.void_);
    if (!palette.boldBackdrop) return;
    // Only Australia/NZ's Southern Cross has a real mini-flag drawer
    // so far (see _drawMiniAustraliaFlag) - boldBackdrop is only ever
    // true where that's wired up.
    if (palette.flagKind != FlagKind.southernCross) return;

    const periodX = _tileW + _gapX;
    const periodY = _tileH + _gapY;
    var row = 0;
    for (double y = -_tileH; y < size.height + _tileH; y += periodY) {
      final rowOffset = row.isOdd ? periodX / 2 : 0.0;
      var col = 0;
      for (double x = -_tileW + rowOffset; x < size.width + _tileW; x += periodX) {
        canvas.save();
        canvas.translate(x + _tileW / 2, y + _tileH / 2);
        canvas.rotate(((row + col).isEven ? -1 : 1) * _tiltRadians);
        canvas.translate(-_tileW / 2, -_tileH / 2);
        // Group alpha for the whole tile (field + canton + stars) in
        // one composite, not per-shape - keeps every tile's flag
        // colours internally consistent instead of layering partial
        // transparencies on top of each other.
        canvas.saveLayer(
          const Rect.fromLTWH(0, 0, _tileW, _tileH),
          Paint()..color = Colors.black.withValues(alpha: _tileOpacity),
        );
        _drawMiniAustraliaFlag(canvas, const Rect.fromLTWH(0, 0, _tileW, _tileH), palette);
        canvas.restore();
        canvas.restore();
        col++;
      }
      row++;
    }
  }

  void _drawMiniAustraliaFlag(Canvas canvas, Rect rect, AppPalette palette) {
    canvas.drawRect(rect, Paint()..color = palette.accent);
    final cantonRect = Rect.fromLTWH(rect.left, rect.top, rect.width * 0.5, rect.height * 0.5);
    drawUnionJack(canvas, cantonRect);

    final starColor = palette.southernCrossRedStars ? nzStarRed : Colors.white;
    final edgeColor = palette.southernCrossRedStars ? Colors.white : null;
    final r = rect.shortestSide * 0.11;
    Offset at(double fx, double fy) => Offset(rect.left + rect.width * fx, rect.top + rect.height * fy);

    // Real Southern Cross fractions (same Wikimedia SVG as
    // theme.dart's australiaPalette/flag_frame.dart border comments):
    // gamma, delta, beta, alpha, epsilon (small).
    final southernCross = <(Offset, int, double)>[
      (at(0.75, 0.167), 7, 1.0),
      (at(0.861, 0.370), 7, 1.0),
      (at(0.625, 0.4375), 7, 1.0),
      (at(0.75, 0.833), 7, 1.0),
      (at(0.80, 0.542), 5, 0.6),
    ];
    final count = (palette.starCount ?? southernCross.length).clamp(0, southernCross.length);
    for (var i = 0; i < count; i++) {
      final (pos, points, scale) = southernCross[i];
      drawStar(canvas, pos, r * scale, points, starColor, edgeColor: edgeColor);
    }
    if (palette.southernCrossCommonwealthStar) {
      drawStar(canvas, at(0.25, 0.75), r * 0.85, 7, starColor, edgeColor: edgeColor);
    }
  }

  @override
  bool shouldRepaint(covariant _FlagBackdropPainter oldDelegate) => oldDelegate.palette != palette;
}
