// screens/conflict_picker_screen.dart
//
// 2026-08-18: step 2 of the conflict-picker plan - "vimdiff instant
// visuals... rather than concentrated heavy reading." Two stacked
// panels (not side-by-side - not enough width on a phone), each showing
// its side's full text with only the differing words underlined and
// tinted, so the eye jumps straight to what changed instead of having
// to read both blocks end to end to spot it. Tap either panel to pick
// it; the file gets rewritten with exactly that span replaced - see
// conflict_scanner.dart's resolveConflict.

import 'package:flutter/material.dart';
import '../theme.dart';
import '../models/repository.dart';
import '../services/conflict_scanner.dart';
import '../services/vault_folder_service.dart';
import '../services/word_diff.dart';

class ConflictPickerScreen extends StatefulWidget {
  final Repository repo;
  final ConflictEntry entry;
  const ConflictPickerScreen({
    super.key,
    required this.repo,
    required this.entry,
  });

  @override
  State<ConflictPickerScreen> createState() => _ConflictPickerScreenState();
}

class _ConflictPickerScreenState extends State<ConflictPickerScreen> {
  bool _resolving = false;

  // 2026-08-18: tapping a panel used to resolve immediately - no second
  // step, no explanation. Real user fear surfaced testing this: "what
  // will happen next, can it be reversed, what am I doing?" This asks
  // first, states plainly what happens, and says exactly how it's
  // recoverable (a backup note - see conflict_scanner.dart's
  // resolveConflict) instead of just asserting "don't worry."
  Future<void> _confirmAndChoose(String label, String chosen) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('Keep this version?',
            style: TextStyle(color: kStar, fontSize: 17)),
        content: Text(
          'This note will be updated to keep "$label" and remove the '
          'other version from it.\n\n'
          'Both full versions are saved first to a folder called '
          '"LocalSync Conflict Backups", visible at the top of your '
          'file list in Obsidian - so if you pick the wrong one you '
          'can still find and copy the other version back yourself. '
          'This app can\'t undo it automatically, but nothing is '
          'deleted for good.',
          style: const TextStyle(color: kStar, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Not now',
                style: TextStyle(color: kTextDim, fontSize: 15)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Keep this version',
                style: TextStyle(color: kStar, fontSize: 15)),
          ),
        ],
      ),
    );
    if (proceed == true) await _choose(chosen);
  }

  Future<void> _choose(String chosen) async {
    setState(() => _resolving = true);
    final vaultFolder = VaultFolderService();
    final path = await vaultFolder.startAccessing(widget.repo.vaultBookmark);
    try {
      if (path != null) {
        await resolveConflict(path, widget.entry, chosen);
      }
    } finally {
      await vaultFolder.stopAccessing(widget.repo.vaultBookmark);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final tooBig = entry.ours.length > maxDiffTokens * 6 ||
        entry.theirs.length > maxDiffTokens * 6;

    return Scaffold(
      backgroundColor: kVoid,
      appBar: AppBar(
        backgroundColor: kVoid,
        title: Text(entry.filePath,
            style: const TextStyle(color: kStar, fontSize: 16)),
      ),
      body: _resolving
          ? const Center(child: CircularProgressIndicator(color: kGreen))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                    "Tap a version to review it, then confirm - nothing "
                    'is changed until you confirm.',
                    style: TextStyle(color: kTextMid, fontSize: 13)),
                const SizedBox(height: 16),
                _ConflictPanel(
                  title: 'Your version',
                  tokens: tooBig
                      ? null
                      : wordDiffOurs(entry.ours, entry.theirs),
                  plainText: entry.ours,
                  highlightColor: Colors.redAccent,
                  onTap: () => _confirmAndChoose('Your version', entry.ours),
                ),
                const SizedBox(height: 16),
                _ConflictPanel(
                  title: entry.when != null
                      ? '${entry.who} - ${entry.when}'
                      : entry.who,
                  tokens: tooBig
                      ? null
                      : wordDiffTheirs(entry.ours, entry.theirs),
                  plainText: entry.theirs,
                  highlightColor: kGreen,
                  onTap: () => _confirmAndChoose(
                      entry.when != null
                          ? '${entry.who} - ${entry.when}'
                          : entry.who,
                      entry.theirs),
                ),
              ],
            ),
    );
  }
}

class _ConflictPanel extends StatelessWidget {
  final String title;
  final List<DiffToken>? tokens; // null -> too big to diff, show plain
  final String plainText;
  final Color highlightColor;
  final VoidCallback onTap;
  const _ConflictPanel({
    required this.title,
    required this.tokens,
    required this.plainText,
    required this.highlightColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kSurface,
          border: Border.all(color: kTextDim),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    color: highlightColor,
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            tokens == null
                ? Text(plainText, style: const TextStyle(color: kStar))
                : Text.rich(
                    TextSpan(
                      children: tokens!
                          .map((t) => TextSpan(
                                text: t.text,
                                style: t.op == DiffOp.equal
                                    ? const TextStyle(color: kStar)
                                    : TextStyle(
                                        color: highlightColor,
                                        decoration: TextDecoration.underline,
                                        decorationColor: highlightColor,
                                        decorationThickness: 2,
                                        fontWeight: FontWeight.bold,
                                      ),
                              ))
                          .toList(),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
