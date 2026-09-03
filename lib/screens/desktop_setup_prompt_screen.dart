// screens/desktop_setup_prompt_screen.dart
//
// 2026-09-03: real gap found, live - "I didn't see anywhere on app to
// download desktop file... there's nothing to tell me what to do on
// the app, it must hold my hand with minimal interaction." The desktop
// setup file (kworld.space/localsync) was only ever mentioned
// reactively (linking_screen.dart's SSH-help dialog, shown only after a
// failed pairing attempt with SSH off) or in settings_screen.dart's (i)
// dialogs, which assume it's already been run. Neither catches a
// first-time user before they even try to pair. This is the first
// proactive mention - inserted right after choosing a tier (see
// sync_files_preview_screen.dart / sync_obsidian_preview_screen.dart's
// _proceed()), before the swipe-to-pair gesture even starts.
//
// Skippable, never blocks pairing - someone who already ran the setup
// file, or knows their desktop's SSH/git is already fine, taps through
// in one beat. Shown once ever (DatabaseService's
// getSeenDesktopSetupPrompt/setSeenDesktopSetupPrompt), not on every
// re-pair - "just make minimal friction for users" when asked whether
// this should repeat.
//
// Storyboarded first (not coded blind) - matches the "First, set up
// your desktop" interstitial reviewed and approved before this file
// was written.

import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/database_service.dart';
import 'linking_screen.dart';

class DesktopSetupPromptScreen extends StatelessWidget {
  const DesktopSetupPromptScreen({super.key});

  Future<void> _continue(BuildContext context) async {
    await DatabaseService().setSeenDesktopSetupPrompt();
    if (!context.mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const LinkingScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kVoid,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Icon(Icons.desktop_windows_outlined, color: kGreen, size: 48),
              const SizedBox(height: 24),
              Text('First, set up your desktop',
                  style: TextStyle(
                      color: kStar,
                      fontSize: 24,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Text(
                  'One file does everything - git, SSH, and your sync '
                  'folder, in one run.',
                  style:
                      TextStyle(color: kTextMid, fontSize: 15, height: 1.5)),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                decoration: BoxDecoration(
                    color: kSurface,
                    border: Border.all(color: kGreen.withValues(alpha: 0.4)),
                    borderRadius: BorderRadius.circular(10)),
                child: Column(
                  children: [
                    Text('kworld.space/localsync',
                        style: TextStyle(
                            color: kGreen,
                            fontFamily: 'monospace',
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text(
                        'Open that on your desktop, download, run it.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: kTextDim, fontSize: 12.5)),
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _continue(context),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: kGreen,
                      foregroundColor: kVoid,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                  child: Text("I've done this - continue",
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => _continue(context),
                  child: Text("Skip, I'll do it later",
                      style: TextStyle(color: kTextMid, fontSize: 14)),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
