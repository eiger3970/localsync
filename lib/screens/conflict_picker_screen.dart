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
import '../services/database_service.dart';
import '../services/device_name.dart';
import '../services/vault_folder_service.dart';
import '../services/word_diff.dart';

// 2026-08-18: "red colour more difficult than green below with same
// text size" - Material's default Colors.redAccent is noticeably
// lower-contrast against a dark background than kGreen's neon punch.
// A brighter, more saturated red reads at the same perceptual loudness.
const _kBrightRed = Color(0xFFFF3B30);

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
  // 2026-08-18: "I'm unclear where I am and what 'Your version' is" -
  // generic label forced the user to work it out by elimination
  // (reading the OTHER side's real device name, then inferring "the
  // other one must be mine"). Same identity system already used for
  // the "who" on the other side (see database_service.dart /
  // device_name.dart) resolves this device's own name too, so both
  // sides are equally explicit - no more asymmetric clarity.
  String _myDeviceName = '';

  @override
  void initState() {
    super.initState();
    _resolveMyDeviceName();
  }

  Future<void> _resolveMyDeviceName() async {
    final saved = await DatabaseService().getDeviceName();
    final name = (saved != null && saved.trim().isNotEmpty)
        ? saved
        : await defaultDeviceName();
    if (mounted) setState(() => _myDeviceName = name);
  }

  // 2026-08-18: tapping a panel used to resolve immediately - no second
  // step, no explanation. Real user fear surfaced testing this: "what
  // will happen next, can it be reversed, what am I doing?" This asks
  // first, states plainly what happens, and says exactly how it's
  // recoverable (a backup note - see conflict_scanner.dart's
  // resolveConflict) instead of just asserting "don't worry."
  //
  // 2026-08-19: two paragraphs of prose replaced with 3 short icon +
  // label lines - "too verbose, more curt, use a list or points" - same
  // "show the shape at a glance, not a paragraph to read" instinct as
  // the Conflicts screen's own 3-icon safety row (conflicts_screen.dart's
  // _SafetyStep). Wording also generalized from "the other version" to
  // a count, since a note can now genuinely have more than 2 stacked
  // versions (see conflict_scanner.dart's ConflictEntry.versions).
  Future<void> _confirmAndChoose(String label, String chosen) async {
    final otherCount = widget.entry.versions.length - 1;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('Keep this version?',
            style: TextStyle(color: kStar, fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DialogPoint(icon: Icons.check_circle, text: 'Keeps "$label"'),
            _DialogPoint(
                icon: Icons.close,
                text: otherCount == 1
                    ? 'Removes the other version from this note'
                    : 'Removes the other $otherCount versions from this note'),
            const _DialogPoint(
                icon: Icons.backup,
                text: 'Every version backed up first, in '
                    '"LocalSync Conflict Backups"'),
          ],
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
    final versions = entry.versions;
    // 2026-08-19: word-diff is inherently pairwise (LCS between exactly
    // two strings) - it only ever generalized to the original ours/
    // theirs case. A note can now carry 3+ stacked unresolved versions
    // (see conflict_scanner.dart's ConflictEntry.versions) after
    // several rounds of the same conflict never being resolved; for
    // that case each panel falls back to plain text (same fallback
    // already used for oversized text below) rather than a diff against
    // an arbitrarily-chosen "other" side, which would just be
    // misleading.
    final useDiff = versions.length == 2 &&
        versions[0].body.length <= maxDiffTokens * 6 &&
        versions[1].body.length <= maxDiffTokens * 6;

    String titleFor(int i) {
      if (i == 0) return _myDeviceName.isEmpty ? 'This device' : _myDeviceName;
      final v = versions[i];
      return v.when != null ? '${v.who} - ${v.when}' : v.who;
    }

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
                Text(
                    versions.length > 2
                        ? "This note has ${versions.length} unresolved "
                            'versions stacked up - they were never fully '
                            'resolved before another change arrived. Tap '
                            'the one to keep; the rest are still saved to '
                            '"LocalSync Conflict Backups".'
                        : "Tap a version to review it, then confirm - "
                            'nothing is changed until you confirm.',
                    style: const TextStyle(color: kStar, fontSize: 15)),
                const SizedBox(height: 16),
                for (var i = 0; i < versions.length; i++) ...[
                  if (i > 0) const SizedBox(height: 16),
                  _ConflictPanel(
                    title: titleFor(i),
                    tokens: !useDiff
                        ? null
                        : (i == 0
                            ? wordDiffOurs(versions[0].body, versions[1].body)
                            : wordDiffTheirs(
                                versions[0].body, versions[1].body)),
                    plainText: versions[i].body,
                    highlightColor: i == 0 ? _kBrightRed : kGreen,
                    onTap: () =>
                        _confirmAndChoose(titleFor(i), versions[i].body),
                  ),
                ],
              ],
            ),
    );
  }
}

/// One short icon + label line in the confirm dialog - see
/// _confirmAndChoose's 2026-08-19 comment for why this replaced two
/// paragraphs of prose.
class _DialogPoint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _DialogPoint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: kGreen, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(color: kStar, fontSize: 15)),
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
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            tokens == null
                ? Text(plainText,
                    style: const TextStyle(color: kStar, fontSize: 17))
                : Text.rich(
                    TextSpan(
                      children: tokens!
                          .map((t) => TextSpan(
                                text: t.text,
                                style: t.op == DiffOp.equal
                                    ? const TextStyle(
                                        color: kStar, fontSize: 17)
                                    : TextStyle(
                                        color: highlightColor,
                                        fontSize: 17,
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
