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

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../models/repository.dart';
import '../services/conflict_scanner.dart';
import '../services/database_service.dart';
import '../services/device_name.dart';
import '../services/ios_app_service.dart';
import '../services/resolved_watchlist.dart';
import '../services/vault_folder_service.dart';
import '../services/word_diff.dart';

// 2026-08-18: "red colour more difficult than green below with same
// text size" - Material's default Colors.redAccent is noticeably
// lower-contrast against a dark background than kGreen's neon punch.
// A brighter, more saturated red reads at the same perceptual loudness.
const _kBrightRed = Color(0xFFFF3B30);

typedef ConflictResolvedResult = ({
  bool resolved,
  String? vaultName,
  String? backupRelPath,
});

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
            _DialogPoint(
                icon: Icons.check_circle,
                color: kGreen,
                text: 'Keeps "$label"'),
            _DialogPoint(
                icon: Icons.cancel,
                color: _kBrightRed,
                text: otherCount == 1
                    ? 'Removes the other version from this note'
                    : 'Removes the other $otherCount versions from this note'),
            // 2026-08-19: real feedback, live - this used check_circle
            // too, same glyph as the "keeps" line above, which read as
            // if the two were related (they're not - this is separate
            // reassurance info, not part of the keep/remove decision).
            // Icons.backup matches conflicts_screen.dart's own
            // _SafetyStep row, which already uses this exact icon for
            // the same concept.
            //
            // 2026-08-20: real feedback, live - the tappable
            // "LocalSync Conflict Backups" link only existed in the
            // post-resolve snackbar (conflicts_screen.dart), one step
            // too late for a user who wants to check it before
            // committing to a choice. Same link here, before the fact -
            // it opens the vault in general (not the specific backup
            // note, which doesn't exist yet at this point), same
            // fallback conflicts_screen.dart already uses since a
            // file-level deep link was proven unreliable on real
            // devices. widget.repo.name is already the vault folder
            // name (set at link time), so this needs no extra vault
            // access beyond what's already in memory.
            _DialogPoint(
              icon: Icons.backup,
              color: kGreen,
              text: 'Every version backed up first, in ',
              linkText: 'LocalSync Conflict Backups',
              onLinkTap: () =>
                  IosAppServiceImpl().openObsidian(vaultName: widget.repo.name),
            ),
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

  // 2026-08-19: pop carries the backup note's location, not just
  // success/failure - real user feedback, live: told to go find
  // "LocalSync Conflict Backups" in Obsidian's file list by hand,
  // "humans don't need to know petty shite, that's for computer
  // machines to deal with." conflicts_screen.dart uses this to offer a
  // direct "View backup" deep-link instead.
  Future<void> _choose(String chosen) async {
    setState(() => _resolving = true);
    final vaultFolder = VaultFolderService();
    final path = await vaultFolder.startAccessing(widget.repo.vaultBookmark);
    String? backupRelPath;
    try {
      if (path != null) {
        backupRelPath = await resolveConflict(path, widget.entry, chosen);
        // 2026-08-20: remember this resolution so a later scan can flag
        // it if it reappears (Obsidian's cache reverting a resolved
        // write) instead of it silently looking like an unremarkable
        // new conflict - see resolved_watchlist.dart.
        await DatabaseService().addResolvedRecords(
          recordsFor(widget.entry, DateTime.now()),
        );
      }
    } finally {
      await vaultFolder.stopAccessing(widget.repo.vaultBookmark);
    }
    if (mounted) {
      Navigator.pop(
        context,
        (
          resolved: true,
          vaultName: path?.split('/').last,
          backupRelPath: backupRelPath,
        ),
      );
    }
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
/// paragraphs of prose. [icon] is always a filled-circle glyph
/// (check_circle / cancel) - real feedback, live: a bare "X" next to a
/// filled check-circle read as inconsistent/"amateur". [color] is
/// semantic (green = keeps/safe, red = removes), not decorative -
/// real feedback, live: the remove line's icon was accidentally still
/// green, the same color as everything else, when it should read as
/// the one negative action in the list.
class _DialogPoint extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  // 2026-08-20: optional tappable suffix - see the backup line's call
  // site above for why. null for the other two lines (keep/remove),
  // which have nothing to link to.
  final String? linkText;
  final VoidCallback? onLinkTap;
  const _DialogPoint({
    required this.icon,
    required this.color,
    required this.text,
    this.linkText,
    this.onLinkTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: linkText == null
                ? Text(text,
                    style: const TextStyle(color: kStar, fontSize: 15))
                : Text.rich(
                    TextSpan(
                      style: const TextStyle(color: kStar, fontSize: 15),
                      children: [
                        TextSpan(text: text),
                        TextSpan(
                          text: linkText,
                          style: const TextStyle(
                            color: kGreen,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = onLinkTap,
                        ),
                      ],
                    ),
                  ),
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
