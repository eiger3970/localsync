// widgets/floating_hearts.dart
//
// 2026-09-17: real ask, live - "SUPPORT, loves hearts pour out
// randomly over screen, floating like bubbles at least to top to
// catch attention of users at top that don't scroll down far." SUPPORT
// sits near the bottom of the About dialog's scrollable content - a
// heart effect confined to that row would never be seen by someone
// who never scrolls that far. This deliberately does NOT emanate from
// SUPPORT's real scroll position (that would need GlobalKey-based
// position tracking, real extra complexity for a decorative touch) -
// instead it's a Stack overlay ABOVE the whole dialog's
// SingleChildScrollView (see home_screen.dart's _showAbout, where this
// is wrapped around `content`), rising from the bottom of the fixed
// dialog viewport to the top of it, regardless of scroll position.
// That's what actually satisfies "catch attention of users that don't
// scroll down far" - the hearts are visible the moment the dialog
// opens, not only once SUPPORT itself is scrolled into view.
//
// Pure CustomPainter, no asset - same reasoning as exploding_letter.dart
// (real Flutter animation, zero file weight). Hearts are drawn by
// painting the real Icons.favorite glyph via TextPainter, not a hand-
// drawn path, so they match the app's own icon language exactly.
import 'dart:math';
import 'package:flutter/material.dart';

class FloatingHearts extends StatefulWidget {
  final Color color;
  const FloatingHearts({super.key, required this.color});

  @override
  State<FloatingHearts> createState() => _FloatingHeartsState();
}

class _FloatingHeartsState extends State<FloatingHearts>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_Heart> _hearts;

  @override
  void initState() {
    super.initState();
    // 2026-09-17: real feedback, live - "come out of the support single
    // heart, and far less, just quiet random floaters." Was 10 hearts
    // spawning at random X across the whole dialog width - now a
    // narrow band near the left edge (roughly where the SUPPORT row's
    // own icon sits - every _AboutHeader icon in this dialog starts at
    // the same left-aligned position), far fewer of them, smaller and
    // slower so they read as a quiet ambient detail, not something
    // competing for attention.
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat();
    final rng = Random(3);
    _hearts = List.generate(
      4,
      (_) => _Heart(
        x: 0.06 + rng.nextDouble() * 0.05,
        startOffset: rng.nextDouble(),
        speed: 0.4 + rng.nextDouble() * 0.3,
        size: 7 + rng.nextDouble() * 6,
        drift: (rng.nextDouble() - 0.5) * 0.25,
        driftPhase: rng.nextDouble() * 2 * pi,
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // IgnorePointer - purely decorative, must never intercept scroll/
    // tap gestures meant for the real dialog content underneath.
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => CustomPaint(
          painter: _HeartsPainter(t: _ctrl.value, hearts: _hearts, color: widget.color),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _Heart {
  final double x; // 0..1, horizontal position
  final double startOffset; // 0..1, staggers each heart's cycle start
  final double speed; // relative rise speed multiplier
  final double size;
  final double drift; // horizontal sway amplitude
  final double driftPhase;
  _Heart({
    required this.x,
    required this.startOffset,
    required this.speed,
    required this.size,
    required this.drift,
    required this.driftPhase,
  });
}

class _HeartsPainter extends CustomPainter {
  final double t; // 0..1, loops
  final List<_Heart> hearts;
  final Color color;
  _HeartsPainter({required this.t, required this.hearts, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    for (final h in hearts) {
      final localT = (t * h.speed + h.startOffset) % 1.0;
      // 2026-09-17: real feedback, live - "hearts don't come from
      // bottom of page, hearts come from heart image at left of word
      // SUPPORT." Was starting at the absolute bottom of the whole
      // overlay (100%) - real tension here, not fully resolved: SUPPORT
      // sits partway down the dialog, and true position-tracking (a
      // GlobalKey on its real icon, following scroll) would mean hearts
      // are only ever visible once scrolled to SUPPORT, undoing the
      // original ask ("catch attention of users that don't scroll down
      // far"). This is the cheaper compromise - origin moved up to 78%
      // instead of 100%, closer to "roughly where SUPPORT sits" without
      // literal tracking, still rising through the top so non-scrollers
      // see them. Flagged to the user as a compromise, not a final
      // answer - real position tracking is the other real option if
      // this isn't close enough.
      final y = size.height * (0.78 - localT * 0.78);
      final sway = sin(localT * 2 * pi + h.driftPhase) * h.drift;
      final x = (size.width * (h.x + sway)).clamp(0.0, size.width);
      // Fade in near the bottom, fade out near the top - never pops in/
      // out abruptly mid-rise.
      final fadeIn = localT < 0.12 ? localT / 0.12 : 1.0;
      final fadeOut = localT > 0.82 ? (1 - localT) / 0.18 : 1.0;
      final opacity = (fadeIn * fadeOut).clamp(0.0, 1.0);
      if (opacity <= 0.02) continue;
      _paintHeartGlyph(
          canvas, Offset(x, y), h.size, color.withValues(alpha: opacity * 0.45));
    }
  }

  void _paintHeartGlyph(Canvas canvas, Offset center, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.favorite.codePoint),
        style: TextStyle(
          fontSize: size,
          fontFamily: Icons.favorite.fontFamily,
          package: Icons.favorite.fontPackage,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _HeartsPainter old) => old.t != t;
}
