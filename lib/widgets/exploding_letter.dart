// widgets/exploding_letter.dart
//
// 2026-09-17: real ask, live - the password-discarded row's icon went
// through several static Material Icon tries (delete_outline read as
// "a bin a hacker could steal from," auto_awesome read as "magic
// stars") before landing on a real animated idea: a letter bursting
// into dust, looping continuously while the info panel is open.
//
// Pure CustomPainter, no image/SVG asset at all - same reasoning as
// ShreddingPasswordField's own fade-and-drift shred animation
// (widgets/shredding_password_field.dart), which already proves this
// exact "real Flutter animation, not a baked asset" pattern works in
// this app. Confirmed with the user: this technique is genuinely
// lighter than shipping a GIF or SVG (zero file weight, and it
// recolors automatically with whichever skin/accent is active) - but
// only for a shape simple enough to describe as points in code. It
// doesn't generalize to replacing real illustrated artwork.
import 'dart:math';
import 'package:flutter/material.dart';

class ExplodingLetter extends StatefulWidget {
  final String letter;
  final Color color;
  final double size;
  const ExplodingLetter({
    super.key,
    required this.letter,
    required this.color,
    this.size = 20,
  });

  @override
  State<ExplodingLetter> createState() => _ExplodingLetterState();
}

class _ExplodingLetterState extends State<ExplodingLetter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<Offset> _basePoints;
  late final List<Offset> _velocities;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _basePoints = _letterPoints(widget.letter);
    final rng = Random(7);
    _velocities = [
      for (final p in _basePoints)
        (Offset(p.dx - 0.5, p.dy - 0.5) * (0.7 + rng.nextDouble() * 0.6)) +
            Offset(rng.nextDouble() - 0.5, rng.nextDouble() - 0.5) * 0.35,
    ];
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => CustomPaint(
          painter: _ExplodePainter(
            t: _ctrl.value,
            base: _basePoints,
            vel: _velocities,
            color: widget.color,
          ),
        ),
      ),
    );
  }
}

// Coarse point-set tracing a capital letter's strokes, normalized to a
// 0..1 box - not font-accurate, just enough to read as "a letter" while
// it briefly holds shape before bursting. Only 'P' is defined (this
// row's only caller); add more letters here if another spot wants this
// effect later.
List<Offset> _letterPoints(String letter) {
  final pts = <Offset>[];
  if (letter == 'P') {
    for (double y = 0.06; y <= 0.94; y += 0.08) {
      pts.add(Offset(0.24, y));
    }
    for (double a = -pi / 2; a <= pi / 2; a += pi / 9) {
      pts.add(Offset(0.24 + 0.30 * cos(a), 0.32 + 0.28 * sin(a)));
    }
  } else {
    // Fallback: a plain circle outline, so an unsupported letter still
    // renders something rather than nothing.
    for (double a = 0; a < 2 * pi; a += pi / 10) {
      pts.add(Offset(0.5 + 0.35 * cos(a), 0.5 + 0.35 * sin(a)));
    }
  }
  return pts;
}

class _ExplodePainter extends CustomPainter {
  final double t; // 0..1, loops via AnimationController.repeat()
  final List<Offset> base;
  final List<Offset> vel;
  final Color color;
  _ExplodePainter({
    required this.t,
    required this.base,
    required this.vel,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Holds the letter shape briefly, then bursts outward and fades -
    // the hold gives the eye a moment to register "a letter" before it
    // vanishes, matching the actual claim ("used once, then gone").
    const holdEnd = 0.18;
    final burstT = t <= holdEnd ? 0.0 : (t - holdEnd) / (1 - holdEnd);
    final fade = 1 - burstT;
    if (fade <= 0.02) return;
    final paint = Paint()..color = color.withValues(alpha: fade.clamp(0, 1));
    for (var i = 0; i < base.length; i++) {
      final p = base[i];
      final v = vel[i];
      final dx = (p.dx + v.dx * burstT) * size.width;
      final dy = (p.dy + v.dy * burstT) * size.height;
      final r = ((1.3 - burstT * 0.8) * (size.width / 20)).clamp(0.4, 2.6);
      canvas.drawCircle(Offset(dx, dy), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ExplodePainter old) => old.t != t;
}
