// screens/sync_files_preview_screen.dart
//
// 2026-08-31: new screen between WelcomeHeroScreen and the real pairing
// flow - a beat to show what "Sync my files" actually gets you before
// diving into setup. The confirm control is the app's own real
// SwapGifSwipeConfirm/LeashSwipeConfirm (person-drags-dog-on-a-leash,
// already used in linking_screen.dart and pairing_screen.dart) - reused
// as-is for consistency, not a new custom slider.

import 'package:flutter/material.dart';
import '../widgets/swap_gif_swipe_confirm.dart';
import '../widgets/shatter_page_route.dart';
import 'linking_screen.dart';
import 'welcome_hero_screen.dart';

class SyncFilesPreviewScreen extends StatelessWidget {
  const SyncFilesPreviewScreen({super.key});

  // This is the one real moment the pastel welcome world meets the
  // app's actual dark UI - shatters into it rather than a plain cut.
  void _proceed(BuildContext context) {
    Navigator.pushReplacement(
        context, ShatterPageRoute(builder: (_) => const LinkingScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [wBg1, wBg2],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back, color: wInkDim),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                      color: wTealBg, borderRadius: BorderRadius.circular(4)),
                  child: Text('FREE',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: wTealDark,
                          letterSpacing: 0.5)),
                ),
                const SizedBox(height: 10),
                Text('Sync my files',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 26,
                        color: wInk)),
                const SizedBox(height: 20),
                Expanded(
                  child: Center(
                    child: _FileTreeIllustration(),
                  ),
                ),
                Text(
                  'No notes app needed — just your files, straight to '
                  'your desktop.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: wInkDim, height: 1.5),
                ),
                const SizedBox(height: 24),
                SwapGifSwipeConfirm(
                  animatedAssetPath: 'assets/gifs/progress_running.gif',
                  onConfirm: () => _proceed(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FileTreeIllustration extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 200,
      child: CustomPaint(painter: _TreePainter()),
    );
  }
}

class _TreePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = wTealDark
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // root -> notes, root -> folder
    canvas.drawLine(const Offset(90, 30), const Offset(50, 78), line);
    canvas.drawLine(const Offset(90, 30), const Offset(115, 88), line);
    // folder -> photo
    canvas.drawLine(const Offset(115, 122), const Offset(112, 145), line);

    _folder(canvas, const Offset(70, 0), 42, wTealBg, wTealDark);
    _doc(canvas, const Offset(28, 78), wTealDark);
    _folder(canvas, const Offset(92, 88), 42, wTealBg, wTealDark);
    _photo(canvas, const Offset(97, 145));
  }

  void _folder(Canvas canvas, Offset o, double w, Color fill, Color stroke) {
    final h = w * 0.7;
    final path = Path()
      ..moveTo(o.dx, o.dy + 8)
      ..lineTo(o.dx, o.dy + h - 2)
      ..quadraticBezierTo(o.dx, o.dy + h, o.dx + 4, o.dy + h)
      ..lineTo(o.dx + w - 4, o.dy + h)
      ..quadraticBezierTo(o.dx + w, o.dy + h, o.dx + w, o.dy + h - 2)
      ..lineTo(o.dx + w, o.dy + 14)
      ..quadraticBezierTo(o.dx + w, o.dy + 10, o.dx + w - 4, o.dy + 10)
      ..lineTo(o.dx + w * 0.45, o.dy + 10)
      ..lineTo(o.dx + w * 0.35, o.dy + 3)
      ..quadraticBezierTo(o.dx + w * 0.3, o.dy, o.dx + w * 0.2, o.dy)
      ..lineTo(o.dx + 4, o.dy)
      ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy + 8)
      ..close();
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
        path,
        Paint()
          ..color = stroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round);
  }

  void _doc(Canvas canvas, Offset o, Color stroke) {
    final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(o.dx, o.dy, 42, 52), const Radius.circular(5));
    canvas.drawRRect(r, Paint()..color = Colors.white);
    canvas.drawRRect(
        r,
        Paint()
          ..color = stroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);
    final linePaint = Paint()
      ..color = stroke
      ..strokeWidth = 2.5;
    canvas.drawLine(
        Offset(o.dx + 8, o.dy + 15), Offset(o.dx + 34, o.dy + 15), linePaint);
    canvas.drawLine(
        Offset(o.dx + 8, o.dy + 26), Offset(o.dx + 34, o.dy + 26), linePaint);
    canvas.drawLine(
        Offset(o.dx + 8, o.dy + 37), Offset(o.dx + 24, o.dy + 37), linePaint);
  }

  void _photo(Canvas canvas, Offset o) {
    final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(o.dx, o.dy, 30, 24), const Radius.circular(4));
    canvas.drawRRect(r, Paint()..color = Colors.white);
    canvas.drawRRect(
        r,
        Paint()
          ..color = wInkDim
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    canvas.drawCircle(Offset(o.dx + 8, o.dy + 8), 2.6, Paint()..color = wInkDim);
    final mtn = Path()
      ..moveTo(o.dx + 3, o.dy + 20)
      ..lineTo(o.dx + 11, o.dy + 11)
      ..lineTo(o.dx + 17, o.dy + 17)
      ..lineTo(o.dx + 23, o.dy + 7)
      ..lineTo(o.dx + 27, o.dy + 20)
      ..close();
    canvas.drawPath(
        mtn,
        Paint()
          ..color = wInkDim
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
