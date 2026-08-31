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
                    child: _PhoneToDesktopFiles(),
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

// Phone -> [notes, docs, photos] -> desktop, real Flutter widgets in a
// Row (not hand-placed CustomPaint offsets - that's what caused the
// off-center bug) - directly echoes WelcomeHeroScreen's phone/desktop
// demo instead of a disconnected file-tree diagram, per direct
// feedback: "doesn't inform or remain consistent with the ease of the
// user syncing device1 to device2."
class _PhoneToDesktopFiles extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const MiniPhoneIcon(color: wTealDark, screenColor: wTealBg),
        const SizedBox(width: 14),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _iconChip(Icons.description_outlined),
            const SizedBox(height: 8),
            _iconChip(Icons.folder_outlined),
            const SizedBox(height: 8),
            _iconChip(Icons.image_outlined),
          ],
        ),
        const SizedBox(width: 14),
        const MiniDesktopIcon(color: wTealDark),
      ],
    );
  }

  Widget _iconChip(IconData icon) {
    return Container(
      width: 34,
      height: 34,
      decoration: const BoxDecoration(color: wTealBg, shape: BoxShape.circle),
      child: Icon(icon, color: wTealDark, size: 18),
    );
  }
}
