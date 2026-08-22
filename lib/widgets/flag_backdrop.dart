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
// Painted BEHIND everything (a Stack, void fill + tiles first, `child`
// last) and only ever into scaffoldBackgroundColor's old territory.
// Never hides functions: every interactive element still sits in its
// own opaque surface, entirely unaffected by whatever's tiled beneath
// it - this widget never draws on top of content, only under it.
//
// 2026-08-22: "your created version is wrong in several factors, stop
// wasting time" - real feedback after a hand-drawn US flag shipped
// with two wrong colours (theme.dart's usPalette comment has the
// detail). Where a real SVG has actually been sourced
// (palette.flagAsset), tiles now render that file directly via
// flutter_svg instead of a hand-coded CustomPainter approximation -
// correct by construction, not by careful colour-matching against a
// reference. This only works here, not for the border: these tiles
// are genuinely unclipped, so there's no 8px-slice ceiling on what
// real fidelity buys (see flag_frame.dart's header for why the border
// stays hand-drawn regardless). Countries without a sourced SVG yet
// fall back to _FlagBackdropPainter's hand-drawn shapes below.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme.dart';
import 'flag_paint.dart';

const _tileW = 60.0;
const _tileH = 30.0;
const _gapX = 18.0;
const _gapY = 18.0;
const _tileOpacity = 0.55;
const _tiltRadians = 0.14;

class FlagBackdrop extends StatelessWidget {
  final Widget child;
  const FlagBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.current;
    final showTiles = palette.boldBackdrop && palette.flagKind != FlagKind.none;
    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: palette.void_)),
        if (showTiles)
          Positioned.fill(
            child: palette.flagAsset != null
                ? _SvgTiledBackdrop(assetPath: palette.flagAsset!)
                : CustomPaint(painter: _FlagBackdropPainter(palette)),
          ),
        child,
      ],
    );
  }
}

// Tiles the real sourced SVG directly - tilt/opacity are layout of
// multiple copies (kept, per explicit direction), not alteration of
// the artwork itself.
class _SvgTiledBackdrop extends StatelessWidget {
  final String assetPath;
  const _SvgTiledBackdrop({required this.assetPath});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        const periodX = _tileW + _gapX;
        const periodY = _tileH + _gapY;
        final tiles = <Widget>[];
        var row = 0;
        for (double y = -_tileH; y < size.height + _tileH; y += periodY) {
          final rowOffset = row.isOdd ? periodX / 2 : 0.0;
          var col = 0;
          for (double x = -_tileW + rowOffset; x < size.width + _tileW; x += periodX) {
            final angle = ((row + col).isEven ? -1 : 1) * _tiltRadians;
            tiles.add(Positioned(
              left: x,
              top: y,
              width: _tileW,
              height: _tileH,
              child: Transform.rotate(
                angle: angle,
                child: Opacity(
                  opacity: _tileOpacity,
                  child: SvgPicture.asset(assetPath, fit: BoxFit.fill),
                ),
              ),
            ));
            col++;
          }
          row++;
        }
        return Stack(children: tiles);
      },
    );
  }
}

// Hand-drawn fallback for any bold skin whose country hasn't had a
// real SVG sourced yet - generalised to dispatch on FlagKind, same as
// the border painter, reusing the same shared primitives
// (flag_paint.dart). Not yet exploited: unlike the border, an
// unclipped tile COULD show Brazil's diamond+circle, Argentina's sun,
// Canada's leaf for real (those are only unshowable in the 8px edge
// border, not here) - left as plain stripes for now, matching their
// existing FlagKind, a real future upgrade rather than a limitation.
class _FlagBackdropPainter extends CustomPainter {
  final AppPalette palette;
  _FlagBackdropPainter(this.palette);

  @override
  void paint(Canvas canvas, Size size) {
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
        _drawMiniFlag(canvas, const Rect.fromLTWH(0, 0, _tileW, _tileH), palette);
        canvas.restore();
        canvas.restore();
        col++;
      }
      row++;
    }
  }

  void _drawMiniFlag(Canvas canvas, Rect rect, AppPalette palette) {
    switch (palette.flagKind) {
      case FlagKind.stripes:
        drawStripes(canvas, rect, palette.flagStripes ?? const [],
            vertical: palette.stripesVertical, weights: palette.stripeWeights);
        break;
      case FlagKind.nordicCross:
        drawNordicCross(canvas, rect, field: Colors.white, cross: palette.accent);
        break;
      case FlagKind.stGeorgesCross:
        drawCenteredCross(canvas, rect, field: Colors.white, cross: palette.accent);
        break;
      case FlagKind.unionJack:
        drawUnionJack(canvas, rect);
        break;
      case FlagKind.starsAndStripes:
        _drawMiniStarsAndStripes(canvas, rect, palette);
        break;
      case FlagKind.southernCross:
        _drawMiniSouthernCross(canvas, rect, palette);
        break;
      case FlagKind.none:
        break;
    }
  }

  void _drawMiniStarsAndStripes(Canvas canvas, Rect rect, AppPalette palette) {
    drawStripes(canvas, rect, palette.flagStripes ?? const []);
    final canton = Rect.fromLTWH(rect.left, rect.top, rect.width * 0.4, rect.height * (7 / 13));
    canvas.drawRect(canton, Paint()..color = usCantonBlue);
    // Representative 3x3 grid, not a literal 50-star count - unclipped
    // and real, but at this tile size 50 individual stars would just
    // be noise, not a recognisable pattern.
    final starR = rect.shortestSide * 0.05;
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 3; col++) {
        final fx = (col + 0.5) / 3;
        final fy = (row + 0.5) / 3;
        drawStar(
          canvas,
          Offset(canton.left + canton.width * fx, canton.top + canton.height * fy),
          starR,
          5,
          Colors.white,
        );
      }
    }
  }

  void _drawMiniSouthernCross(Canvas canvas, Rect rect, AppPalette palette) {
    canvas.drawRect(rect, Paint()..color = palette.accent);
    final cantonRect = Rect.fromLTWH(rect.left, rect.top, rect.width * 0.5, rect.height * 0.5);
    drawUnionJack(canvas, cantonRect);

    final starColor = palette.southernCrossRedStars ? nzStarRed : Colors.white;
    final edgeColor = palette.southernCrossRedStars ? Colors.white : null;
    final r = rect.shortestSide * 0.11;
    Offset at(double fx, double fy) => Offset(rect.left + rect.width * fx, rect.top + rect.height * fy);

    // Real Southern Cross fractions (same Wikimedia SVG as
    // theme.dart's australiaPalette/flag_frame.dart border comments):
    // gamma, delta, beta, alpha, epsilon (small). NZ has no sourced
    // SVG yet, so it reuses these same relative positions.
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
