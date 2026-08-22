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
//
// 2026-08-22: "Australia and UK union jacks are wrong... use the svgs
// I provided" - real feedback, correct. The hand-drawn drawUnionJack
// approximation was being used for every country regardless of
// whether a real SVG existed, on the assumption that an 8px clip
// leaves no room for fidelity to matter. True for stripes/crosses
// (simple axis-aligned bands - already accurate once colours and
// proportions match) but false for FlagKind.unionJack and
// southernCross: the Union Jack canton concentrates diagonal/cross
// detail right at the corner the border actually reveals, and the
// hand-drawn version's inaccuracy showed there. Those two kinds now
// load and draw the real sourced picture (flag_paint.dart's
// loadFlagSvgPicture/drawPictureScaled) wherever palette.flagAsset is
// set, falling back to the hand-drawn shapes only when no SVG has
// been sourced for that country yet.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme.dart';
import 'flag_paint.dart';

// Kinds whose real SVG (where sourced) is worth loading for the
// border specifically - see flag_paint.dart's loadFlagSvgPicture doc
// comment for why this is scoped to just these two rather than every
// sourced country: stripes/crosses are simple axis-aligned bands,
// already accurate once colour/proportions match by hand, so loading
// a real picture for those would cost an async load for zero visible
// difference. unionJack and southernCross have diagonal/canton detail
// concentrated right at the corner the border actually reveals.
const _kindsWorthRealSvg = {FlagKind.unionJack, FlagKind.southernCross};

class FlagFrame extends StatefulWidget {
  final Widget child;
  final double thickness;
  const FlagFrame({super.key, required this.child, this.thickness = 8});

  @override
  State<FlagFrame> createState() => _FlagFrameState();
}

class _FlagFrameState extends State<FlagFrame> {
  String? _loadedPath;
  PictureInfo? _pictureInfo;

  void _ensureLoaded(AppPalette palette) {
    final wantPath = _kindsWorthRealSvg.contains(palette.flagKind) ? palette.flagAsset : null;
    if (wantPath == _loadedPath) return;
    _loadedPath = wantPath;
    _pictureInfo?.picture.dispose();
    _pictureInfo = null;
    if (wantPath == null) return;
    loadFlagSvgPicture(wantPath).then((info) {
      if (!mounted || _loadedPath != wantPath) {
        info.picture.dispose();
        return;
      }
      setState(() => _pictureInfo = info);
    });
  }

  @override
  void dispose() {
    _pictureInfo?.picture.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.current;
    _ensureLoaded(palette);
    if (palette.flagKind == FlagKind.none) return widget.child;
    // 2026-08-22: was CustomPaint(child: Padding(...)) - shrank
    // whatever it wrapped by `thickness` on every side to make room
    // for the border. Fine while this only wrapped Home's body, but
    // now that it wraps the whole app (main.dart's MaterialApp.builder,
    // AppBar included) that 16px width loss pushed an already-tight
    // AppBar row (title + repo status + kebab) into a real overflow -
    // a regression this change introduced, not a pre-existing bug.
    // Stack overlay instead: content keeps its full original layout,
    // the border paints on top of just its outermost `thickness`
    // band. IgnorePointer so the overlay never swallows a tap even
    // though CustomPaint alone wouldn't have hit-tested here anyway.
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _FlagFramePainter(palette: palette, thickness: widget.thickness, svgPicture: _pictureInfo),
            ),
          ),
        ),
      ],
    );
  }
}

class _FlagFramePainter extends CustomPainter {
  final AppPalette palette;
  final double thickness;
  final PictureInfo? svgPicture;
  _FlagFramePainter({required this.palette, required this.thickness, this.svgPicture});

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
        drawStripes(canvas, full, palette.flagStripes ?? const [],
            vertical: palette.stripesVertical, weights: palette.stripeWeights);
        break;
      case FlagKind.nordicCross:
        drawNordicCross(canvas, full, field: Colors.white, cross: palette.accent);
        break;
      case FlagKind.stGeorgesCross:
        drawCenteredCross(canvas, full, field: Colors.white, cross: palette.accent);
        break;
      case FlagKind.unionJack:
        if (svgPicture != null) {
          drawPictureScaled(canvas, svgPicture!, full);
        } else {
          drawUnionJack(canvas, full);
        }
        break;
      case FlagKind.starsAndStripes:
        drawStripes(canvas, full, palette.flagStripes ?? const []);
        _drawUsCanton(canvas, size);
        _paintCantonStars(canvas, size);
        break;
      case FlagKind.southernCross:
        if (svgPicture != null) {
          // Real picture already contains the correct field + canton
          // internally - draws the whole real flag at screen scale,
          // same clip-reveals-the-edge principle as every other kind,
          // just from real artwork instead of hand-drawn shapes.
          drawPictureScaled(canvas, svgPicture!, full);
        } else {
          canvas.drawRect(full, Paint()..color = palette.accent);
          // Canton is exactly half the flag's width and height - real
          // Wikimedia Australia SVG (viewBox 0 0 10080 5040, canton
          // clip 0,0-6,3 of a 12x6 box), confirmed 2026-08-22. True of
          // NZ too - same Blue Ensign proportions.
          drawUnionJack(canvas, Rect.fromLTWH(0, 0, size.width * 0.5, size.height * 0.5));
        }
        // Real star positions are interior/non-edge-touching either
        // way (see file header) - this stays the point-emblem
        // approach regardless of whether the field/canton above came
        // from a real picture or hand-drawn shapes.
        _paintSouthernCrossStars(canvas, size);
        break;
      case FlagKind.none:
        break;
    }
    canvas.restore();
  }

  // ── Edge-spanning shapes (drawn at full screen scale, revealed only
  //    through the clip set up in paint()) ──────────────────────────

  void _drawUsCanton(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width * 0.4, size.height * (7 / 13));
    canvas.drawRect(rect, Paint()..color = usCantonBlue);
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
      drawStar(canvas, p, r, 5, Colors.white);
    }
  }

  void _paintSouthernCrossStars(Canvas canvas, Size size) {
    final starColor = palette.southernCrossRedStars ? nzStarRed : Colors.white;
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
      drawStar(canvas, positions[i], small ? r * 0.6 : r, small ? 5 : 7, starColor, edgeColor: edgeColor);
    }

    if (palette.southernCrossCommonwealthStar) {
      // Real position (25%, 75%) - x snapped to the left edge since
      // the canton anchors it there; y matches the real fraction.
      drawStar(canvas, Offset(half, size.height * 0.75), r * 0.85, 7, starColor, edgeColor: edgeColor);
    }
  }

  @override
  bool shouldRepaint(covariant _FlagFramePainter oldDelegate) =>
      oldDelegate.palette != palette ||
      oldDelegate.thickness != thickness ||
      oldDelegate.svgPicture != svgPicture;
}
