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
//
// 2026-09-03: real device feedback, live, right after shipping -
// "noobs don't know what git and ssh are and don't care, need normie
// words" - body copy dropped git/SSH/IP-address jargon entirely,
// down to what it actually does for the reader. "unsure about desktop
// having to run the IP address, as the app satellite is very handy" -
// fair, the satellite icon already solves IP discovery elegantly, so
// this screen's own copy shouldn't sell that part of the setup file's
// job. "text below is too dark and small" - kTextDim/12.5 bumped to
// kTextMid/13.5. "I'm confused with 2 similar choices" - "I've done
// this" and "Skip" led to the exact same place doing the exact same
// thing (see the old _continue duplicated across both buttons below) -
// two labels for one behavior is confusion, not choice. Collapsed to
// one "Continue" button.
//
// 2026-09-04: real feedback, live - "why is [tap to copy] here, this
// seems to just add confusion and an unnecessary step?" Fair - a
// 2026-09-03 fix made this URL tappable (copy-to-clipboard) because it
// used to look tappable but do nothing, and that read as broken. But
// this is a short, memorable URL, not a long path like the git bare
// repo one - copy/paste solves a real problem for THAT, not for eleven
// characters someone can just read and type. Removed the tap/copy
// mechanic entirely instead of building it out further: this is now
// plain, non-interactive text with no border implying a button, so
// there's nothing to feel broken or add a step over reading and typing
// it directly.

import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/database_service.dart';
import 'linking_screen.dart';

class DesktopSetupPromptScreen extends StatelessWidget {
  const DesktopSetupPromptScreen({super.key});

  static const _url = 'kworld.space/localsync';

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
                  'One file gets your desktop ready to connect - '
                  'nothing to type or configure by hand.',
                  style:
                      TextStyle(color: kTextMid, fontSize: 15, height: 1.5)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(_url,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: kGreen,
                            fontFamily: 'monospace',
                            fontSize: 18,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text('Open that on your desktop.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: kTextMid, fontSize: 13.5)),
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
                  child: Text('Continue',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
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
