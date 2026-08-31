// screens/sync_obsidian_preview_screen.dart
//
// 2026-08-31: PKM-path sibling of sync_files_preview_screen.dart - see
// that file's header for the shared reasoning. The illustration here is
// a deliberately ABSTRACT bi-directional node/bubble graph, not any one
// PKM app's actual logo (avoids the Obsidian-branding/trademark issue
// flagged directly, while still nodding at Logseq's bubble-graph look
// alongside Obsidian's own graph view - the long-term goal is Logseq as
// the primary PKM app once it's functional enough, per direct note).

import 'package:flutter/material.dart';
import '../widgets/swap_gif_swipe_confirm.dart';
import '../widgets/shatter_page_route.dart';
import 'linking_screen.dart';
import 'welcome_hero_screen.dart';

class SyncObsidianPreviewScreen extends StatelessWidget {
  const SyncObsidianPreviewScreen({super.key});

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
            colors: [wBg1, Color(0xFFF1ECFA)],
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
                      color: wVioletBg,
                      borderRadius: BorderRadius.circular(4)),
                  child: Text('PRO · from \$24.99',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: wVioletDark,
                          letterSpacing: 0.5)),
                ),
                const SizedBox(height: 10),
                Text('Sync my Obsidian notes',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 26,
                        color: wInk),
                    textAlign: TextAlign.center),
                const SizedBox(height: 20),
                Expanded(
                  child: Center(child: _GraphIllustration()),
                ),
                Text('Links your whole vault.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: wInkDim)),
                Text('Real conflict protection built in.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: wInkDim)),
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

class _GraphIllustration extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 200,
      child: CustomPaint(painter: _GraphPainter()),
    );
  }
}

class _GraphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final nodes = <Offset, double>{
      const Offset(75, 15): 12,
      const Offset(120, 50): 10,
      const Offset(50, 70): 14,
      const Offset(95, 105): 11,
      const Offset(15, 125): 9,
      const Offset(135, 130): 9,
    };
    final edges = [
      [const Offset(75, 15), const Offset(120, 50)],
      [const Offset(75, 15), const Offset(50, 70)],
      [const Offset(120, 50), const Offset(95, 105)],
      [const Offset(50, 70), const Offset(95, 105)],
      [const Offset(50, 70), const Offset(15, 125)],
      [const Offset(95, 105), const Offset(135, 130)],
    ];

    final linePaint = Paint()
      ..color = wVioletDark
      ..strokeWidth = 2.5;
    for (final e in edges) {
      canvas.drawLine(e[0], e[1], linePaint);
    }

    final fill = Paint()..color = wVioletBg;
    final stroke = Paint()
      ..color = wVioletDark
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    nodes.forEach((center, r) {
      canvas.drawCircle(center, r, fill);
      canvas.drawCircle(center, r, stroke);
    });

    // small bubble-cluster hint, generic PKM nod (Logseq-style bubbles)
    canvas.drawCircle(const Offset(200, 155), 7, fill);
    canvas.drawCircle(const Offset(200, 155), 7, stroke);
    canvas.drawCircle(const Offset(214, 149), 4.5, fill);
    canvas.drawCircle(const Offset(214, 149), 4.5, stroke);
    canvas.drawCircle(const Offset(212, 162), 3.5, fill);
    canvas.drawCircle(const Offset(212, 162), 3.5, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
