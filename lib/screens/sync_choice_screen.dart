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
// 2026-08-28: real feedback, live - "still not confident about hand
// holding git file path setup on desktop and phone." Today's earlier
// fixes (desktop username field, suggested-path button, real path in
// the folder-picker disclosure) all only help once someone's already
// found Settings - nothing ever sent a first-time user there before
// attempting to pair, so the very first real connection attempt would
// fail against this developer's own build-time desktop IP, with no clue
// why. Soft nudge, not a hard block (matches this app's established
// "not naggy" precedent elsewhere) - a visible banner when Settings has
// genuinely never been touched, with a direct way there, but the choice
// cards below stay tappable regardless.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../models/repository.dart';
import '../services/database_service.dart';
import '../features/linking/linking_controller.dart';
import 'linking_screen.dart';
import 'settings_screen.dart';

class SyncChoiceScreen extends StatefulWidget {
  const SyncChoiceScreen({super.key});

  @override
  State<SyncChoiceScreen> createState() => _SyncChoiceScreenState();
}

class _SyncChoiceScreenState extends State<SyncChoiceScreen> {
  // null while still checking - avoids a one-frame flash either way.
  bool? _needsSettings;

  @override
  void initState() {
    super.initState();
    _checkSettings();
  }

  Future<void> _checkSettings() async {
    final db = DatabaseService();
    final user = await db.getDesktopUser();
    final ip = await db.getDesktopIp();
    final path = await db.getBareRepoPath();
    if (!mounted) return;
    // Only nudge when NONE have ever been set - even one real override
    // means this isn't a genuinely untouched first run.
    setState(() {
      _needsSettings = (user == null || user.trim().isEmpty) &&
          (ip == null || ip.trim().isEmpty) &&
          (path == null || path.trim().isEmpty);
    });
  }

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
              if (_needsSettings == true) ...[
                const SizedBox(height: 20),
                _SettingsNudge(
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen())),
                ),
              ],
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

class _SettingsNudge extends StatelessWidget {
  final VoidCallback onTap;
  const _SettingsNudge({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kSurface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amber, width: 1),
          ),
          child: Row(
            children: [
              const Icon(Icons.settings_outlined, color: Colors.amber, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('First time? Check your desktop connection first',
                        style: TextStyle(
                            color: kStar, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('Desktop username, IP address, and folder path',
                        style: TextStyle(color: kTextMid, fontSize: 11.5)),
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
