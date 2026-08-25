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
        title: Text('Keep this version?',
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
            // 2026-08-20: tappable link, same as the post-resolve
            // snackbar (conflicts_screen.dart) - opens the vault in
            // general (widget.repo.name is already the vault folder
            // name, set at link time, no extra vault access needed).
            // A same-session A/B test confirmed which note Obsidian
            // shows afterward tracks whatever was on-screen in Obsidian
            // right before switching away, not this button - reverted
            // an earlier "open Obsidian" rewording that tried to hedge
            // around that, per direct instruction not to.
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
          // 2026-08-20: real feedback, live - kTextDim read as a
          // disabled/dead button, not a live but de-emphasized one.
          // kTextMid is still visibly secondary next to "Keep this
          // version"'s bright kStar, without looking inert.
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Not now',
                style: TextStyle(color: kTextMid, fontSize: 15)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Keep this version',
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
      // 2026-08-22: explicit kVoid removed - see settings_screen.dart's
      // matching comment. ThemeData.scaffoldBackgroundColor is now
      // transparent so the global FlagBackdrop shows through instead.
      appBar: AppBar(
        backgroundColor: kVoid,
        title: Text(entry.filePath,
            style: TextStyle(color: kStar, fontSize: 16)),
      ),
      body: _resolving
          ? Center(child: CircularProgressIndicator(color: kGreen))
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
                    style: TextStyle(color: kStar, fontSize: 15)),
                const SizedBox(height: 16),
                // 2026-08-25: real feedback, live - "picking the top red
                // version or the bottom green version is too much eye
                // bleed. What I need is the 2 versions in a vimdiff
                // screen, which is very easy to spot the differences
                // visually... the phone might need to be held from
                // portrait to landscape." Stacked full-width panels with
                // bold colored underlined text replaced with genuine
                // side-by-side columns (same word-diff algorithm - only
                // the layout changed) and a soft background tint instead
                // of loud colored/underlined text for what differs -
                // matches how vimdiff itself reads (highlighted region,
                // not shouting text). Landscape gives each column real
                // width; portrait still works, just narrower.
                if (useDiff && versions.length == 2)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _ConflictPanel(
                            title: titleFor(0),
                            tokens: wordDiffOurs(
                                versions[0].body, versions[1].body),
                            plainText: versions[0].body,
                            highlightColor: _kBrightRed,
                            onTap: () => _confirmAndChoose(
                                titleFor(0), versions[0].body),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _ConflictPanel(
                            title: titleFor(1),
                            tokens: wordDiffTheirs(
                                versions[0].body, versions[1].body),
                            plainText: versions[1].body,
                            highlightColor: kGreen,
                            onTap: () => _confirmAndChoose(
                                titleFor(1), versions[1].body),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  for (var i = 0; i < versions.length; i++) ...[
                    if (i > 0) const SizedBox(height: 16),
                    _ConflictPanel(
                      title: titleFor(i),
                      tokens: null,
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
                    style: TextStyle(color: kStar, fontSize: 15))
                : Text.rich(
                    TextSpan(
                      style: TextStyle(color: kStar, fontSize: 15),
                      children: [
                        TextSpan(text: text),
                        TextSpan(
                          text: linkText,
                          style: TextStyle(
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
        height: double.infinity,
        padding: const EdgeInsets.all(10),
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
                    fontSize: 14,
                    fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            // 2026-08-25: real feedback, live - "too much eye bleed."
            // Bold + underline + saturated color on the changed text
            // itself read as shouting. A soft background wash (like a
            // highlighter marker, ~20% opacity) behind just the
            // differing words instead - equal text stays plain, so the
            // eye still jumps straight to what changed, without every
            // difference looking like an alarm.
            tokens == null
                ? Text(plainText,
                    style: TextStyle(color: kStar, fontSize: 14))
                : Text.rich(
                    TextSpan(
                      children: tokens!
                          .map((t) => TextSpan(
                                text: t.text,
                                style: t.op == DiffOp.equal
                                    ? TextStyle(color: kStar, fontSize: 14)
                                    : TextStyle(
                                        color: kStar,
                                        fontSize: 14,
                                        backgroundColor:
                                            highlightColor.withValues(alpha: 0.28),
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
