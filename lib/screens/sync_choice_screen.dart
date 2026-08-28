// screens/sync_choice_screen.dart
//
// 2026-08-27: real feedback, live - "Tier0 screen that's not how a
// normie will setup. A normie needs the hand held from install of app...
// PKM terminology is too much." Before this, a fresh install's very
// first screen was straight into LinkingScreen's "PKM VAULT SETUP" -
// drag-a-key-into-a-vault-lock imagery, before a Tier 0 user (who wants
// nothing to do with PKM/Obsidian at all) ever saw anything relevant to
// them. This is the actual first screen now: plain language, two equal
// choices, no jargon, before any pairing/vault UI appears at all.
//
// Sets LinkingController.preferredMode, then pushes into the existing
// LinkingScreen - the drag-to-pair gesture and everything else about
// setup stays exactly what it already was (same SSH pairing either way,
// same "secret sauce" vault-linking sequence for the PKM choice) - only
// the entry point and the words around it change, per the deliberate
// scope decision to not touch how any of that actually works.
//
// 2026-08-28: a same-day round added a "check Settings first" banner
// directly on this screen - reverted same day, real feedback, live:
// "this must be the welcome page with hero stuff... I see technical
// mumbo jumbo... a welcome needs warm fuzzy positive easy feelings, not
// verbose text." The underlying need (warn a first-time user before
// they hit a real connection failure) was real, but this exact screen -
// the one this file's own 2026-08-27 header exists specifically to keep
// jargon-free - was the wrong place for it. Moved to LinkingScreen's own
// Stage 1 instead (see its own 2026-08-28 comment) - a technical-setup
// context where a Settings reminder actually belongs, not the warm
// first hello.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../models/repository.dart';
import '../features/linking/linking_controller.dart';
import 'linking_screen.dart';

class SyncChoiceScreen extends StatelessWidget {
  const SyncChoiceScreen({super.key});

  void _choose(BuildContext context, SyncMode mode) {
    context.read<LinkingController>().preferredMode = mode;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const LinkingScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kVoid,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('What do you want to sync?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: kStar,
                      fontSize: 24,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                'Both sync straight between your own phone and desktop - '
                'no cloud, no account.',
                textAlign: TextAlign.center,
                style: TextStyle(color: kTextMid, fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 40),
              _ChoiceCard(
                icon: Icons.folder_outlined,
                title: 'Just my files',
                subtitle: 'Photos, documents, any files - no notes app '
                    'needed',
                onTap: () => _choose(context, SyncMode.genericFolder),
              ),
              const SizedBox(height: 16),
              _ChoiceCard(
                icon: Icons.auto_stories_rounded,
                title: 'My Obsidian notes',
                subtitle: 'Links your Obsidian vault, with real conflict '
                    'protection built in',
                onTap: () => _choose(context, SyncMode.obsidianVault),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kSurface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(icon, color: kGreen, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: kStar,
                            fontSize: 17,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: TextStyle(
                            color: kTextMid, fontSize: 13, height: 1.3)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: kTextDim),
            ],
          ),
        ),
      ),
    );
  }
}
