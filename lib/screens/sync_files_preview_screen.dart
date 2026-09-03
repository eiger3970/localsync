// screens/sync_files_preview_screen.dart
//
// 2026-08-31: new screen between WelcomeHeroScreen and the real pairing
// flow - a beat to show what "Sync my files" actually gets you before
// diving into setup. The confirm control is the app's own real
// SwapGifSwipeConfirm/LeashSwipeConfirm (person-drags-dog-on-a-leash,
// already used in linking_screen.dart and pairing_screen.dart) - reused
// as-is for consistency, not a new custom slider.

import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../widgets/swap_gif_swipe_confirm.dart';
import '../widgets/shatter_page_route.dart';
import 'desktop_setup_prompt_screen.dart';
import 'linking_screen.dart';
import 'welcome_hero_screen.dart';

class SyncFilesPreviewScreen extends StatelessWidget {
  const SyncFilesPreviewScreen({super.key});

  // This is the one real moment the pastel welcome world meets the
  // app's actual dark UI - shatters into it rather than a plain cut.
  //
  // 2026-09-03: real gap found, live - "there's nothing to tell me
  // what to do on the app... where does the user know to download and
  // run the desktop file?" Shatters into DesktopSetupPromptScreen
  // instead of straight to LinkingScreen the first time only - it
  // handles its own onward navigation once continued/skipped, and
  // marks itself seen so a returning user (or someone pairing a second
  // device) goes straight through as before.
  Future<void> _proceed(BuildContext context) async {
    final seen = await DatabaseService().getSeenDesktopSetupPrompt();
    if (!context.mounted) return;
    Navigator.pushReplacement(
        context,
        ShatterPageRoute(
            builder: (_) => seen
                ? const LinkingScreen()
                : const DesktopSetupPromptScreen()));
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
                    child: PhoneToDesktopFlow(
                      color: wTealDark,
                      screenColor: wTealBg,
                      travelerIcon: Icons.insert_drive_file_outlined,
                    ),
                  ),
                ),
                Text(
                  'No notes app needed - your files, kept in sync '
                  'between your phone and your desktop, both ways.',
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

