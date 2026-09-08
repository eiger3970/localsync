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
import 'backup_compare_screen.dart';
import 'merge_picker_screen.dart';

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
  // 2026-09-08: real feedback, live - the confirm dialog below used to
  // unconditionally claim "Removes the other version" while the code
  // actually kept it as a collapsed reference - a real mismatch between
  // promise and behavior. Now genuinely tracks which is true so the
  // dialog is never wrong, whichever way Settings has this configured.
  bool _keepLeftoverInNote = false;

  @override
  void initState() {
    super.initState();
    _resolveMyDeviceName();
    _loadKeepLeftoverSetting();
  }

  Future<void> _loadKeepLeftoverSetting() async {
    final value = await DatabaseService().getKeepLeftoverInNote();
    if (mounted) setState(() => _keepLeftoverInNote = value);
  }

  // 2026-09-07: real feedback, live - "needs a little i for info/
  // details" on both KEEP BOTH and MERGE PIECES INSTEAD, since neither
  // button's name alone explains what it actually does or how the two
  // differ. Same plain title+message dialog pattern settings_screen.dart
  // already uses for its own (i) buttons.
  void _showInfo(String title, String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kSurface,
        title: Text(title, style: TextStyle(color: kStar, fontSize: 16)),
        content: Text(message,
            style: TextStyle(color: kTextMid, fontSize: 13, height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Got it', style: TextStyle(color: kGreen)),
          ),
        ],
      ),
    );
  }

  // 2026-09-07: real feedback, live - "still too afraid to tap KEEP
  // BOTH. The info needs clear non verbose text... that it's reversible
  // or an undo or it's backed up and a link to the backup, so it's easy
  // for a user to recover with little brain strain." Same short
  // icon+point shape as _confirmAndKeepBoth's own dialog (not a
  // paragraph) - the safety facts (backed up, nothing deleted) lead,
  // ordering logic comes last since it matters less to "am I safe."
  void _showKeepBothInfo() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kSurface,
        title: Text('Keep both', style: TextStyle(color: kStar, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DialogPoint(
              icon: Icons.backup,
              color: kGreen,
              text: 'Every version backed up first, in ',
              linkText: 'LocalSync/Conflict Backups',
              onLinkTap: () =>
                  IosAppServiceImpl().openObsidian(vaultName: widget.repo.name),
            ),
            _DialogPoint(
              icon: Icons.visibility,
              color: kGreen,
              text: 'Nothing hidden - both texts stay as plain, visible '
                  'paragraphs in the note',
            ),
            // 2026-09-08: real feedback, live - "one tap" undo, not just
            // "delete by hand." Now a real button (Conflicts screen's
            // own "merged conflicts" list, conflict_scanner.dart's
            // undoKeepBoth) that swaps this exact note back to an
            // active conflict - available indefinitely, not just while
            // the backup file happens to still exist.
            _DialogPoint(
              icon: Icons.undo,
              color: kGreen,
              text: 'Changed your mind? One tap undoes this - Conflicts '
                  'screen → Merged conflicts',
            ),
            _DialogPoint(
              icon: Icons.sort,
              color: kGreen,
              text: 'Put in time order only if every version starts with '
                  'a clock time - otherwise left as they arrived',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Got it', style: TextStyle(color: kGreen)),
          ),
        ],
      ),
    );
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
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
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
                text: _keepLeftoverInNote
                    ? (otherCount == 1
                        ? 'Keeps the other version too, collapsed for reference'
                        : 'Keeps the other $otherCount versions too, collapsed for reference')
                    : (otherCount == 1
                        ? 'Removes the other version from this note'
                        : 'Removes the other $otherCount versions from this note')),
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
              linkText: 'LocalSync/Conflict Backups',
              onLinkTap: () =>
                  IosAppServiceImpl().openObsidian(vaultName: widget.repo.name),
            ),
            const SizedBox(height: 8),
            // 2026-09-08: real feedback, live - "gone entirely" (today)
            // vs "I need all or part of that data onto this device"
            // (2026-08-25's own explicit ask) are genuinely opposite
            // wants, not a bug to pick one winner for - a per-resolution
            // toggle right here beats a buried Settings-screen entry
            // nobody would find in the moment it actually matters.
            // Changing it here also updates the saved default via
            // DatabaseService, so the next resolution starts from
            // whatever was picked last.
            InkWell(
              onTap: () {
                final next = !_keepLeftoverInNote;
                setDialogState(() {});
                setState(() => _keepLeftoverInNote = next);
                DatabaseService().setKeepLeftoverInNote(next);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                        _keepLeftoverInNote
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        color: kGreen,
                        size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          'Keep the other version too, collapsed for '
                          'reference in this note',
                          style: TextStyle(color: kTextMid, fontSize: 13)),
                    ),
                  ],
                ),
              ),
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
      ),
    );
    if (proceed == true) await _choose(chosen);
  }

  // 2026-08-19: pop carries the backup note's location, not just
  // success/failure - real user feedback, live: told to go find
  // "LocalSync/Conflict Backups" in Obsidian's file list by hand,
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

  // 2026-09-07: real feedback, live - "the app is supposed to fix" a
  // conflict where both sides are genuinely separate, real entries (this
  // user's case: two different journal moments landing as one conflict)
  // - every existing action here either picks one side or requires
  // manually assembling pieces (MERGE PIECES INSTEAD below). This is the
  // one-tap "both belong here" fix - see conflict_scanner.dart's
  // mergeConflictKeepingBoth for what it actually writes.
  Future<void> _confirmAndKeepBoth() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kSurface,
        title: Text('Keep both versions?',
            style: TextStyle(color: kStar, fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DialogPoint(
                icon: Icons.check_circle,
                color: kGreen,
                text: widget.entry.versions.length > 2
                    ? 'Keeps every version, as plain text'
                    : 'Keeps both versions, as plain text'),
            _DialogPoint(
                icon: Icons.sort,
                color: kGreen,
                text: 'Ordered by time when both start with a clock '
                    'time - otherwise left as they are'),
            _DialogPoint(
              icon: Icons.backup,
              color: kGreen,
              text: 'Every version backed up first, in ',
              linkText: 'LocalSync/Conflict Backups',
              onLinkTap: () =>
                  IosAppServiceImpl().openObsidian(vaultName: widget.repo.name),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Not now',
                style: TextStyle(color: kTextMid, fontSize: 15)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Keep both',
                style: TextStyle(color: kStar, fontSize: 15)),
          ),
        ],
      ),
    );
    if (proceed == true) await _keepBoth();
  }

  Future<void> _keepBoth() async {
    setState(() => _resolving = true);
    final vaultFolder = VaultFolderService();
    final path = await vaultFolder.startAccessing(widget.repo.vaultBookmark);
    String? backupRelPath;
    try {
      if (path != null) {
        backupRelPath = await mergeConflictKeepingBoth(path, widget.entry);
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
                            '"LocalSync/Conflict Backups".'
                        : "Tap a version to review it, then confirm - "
                            'nothing is changed until you confirm.',
                    style: TextStyle(color: kStar, fontSize: 15)),
                const SizedBox(height: 8),
                // 2026-09-07: real feedback, live - "the button on the
                // top right of Conflicts is better placed in the actual
                // opened conflict... for each backup." Moved here from
                // conflicts_screen.dart's app bar (a global, unscoped
                // list) - this one only ever shows backups that belong
                // to this exact note, see BackupCompareListScreen.
                // noteFilePath's own doc.
                InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BackupCompareListScreen(
                        repo: widget.repo,
                        noteFilePath: entry.filePath,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.difference_outlined,
                            color: kTextMid, size: 16),
                        const SizedBox(width: 6),
                        Text('Compare with a backup',
                            style: TextStyle(
                                color: kTextMid,
                                fontSize: 13,
                                decoration: TextDecoration.underline)),
                      ],
                    ),
                  ),
                ),
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
                if (useDiff && versions.length == 2) ...[
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
                            // 2026-08-26: real key, not ordinal position -
                            // conflict_vimdiff_preview_test.dart used to
                            // tap this panel via find.byType(InkWell).at(1),
                            // which broke the moment any other InkWell-
                            // based widget (the new "MERGE PIECES INSTEAD"
                            // button below) got added anywhere on this
                            // screen. A key survives that kind of change.
                            key: const Key('conflict_panel_theirs'),
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
                  ),
                  const SizedBox(height: 14),
                  // 2026-08-26: premium tier from docs/pricing-tiers.md -
                  // "automatic - put/yank individual pieces from each
                  // side," not just picking one whole side above. Same
                  // useDiff gate (pairwise, size-capped) since
                  // line_diff.dart's sentence refinement only makes
                  // sense for the same 2-version case the word-diff view
                  // already requires.
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final result =
                                await Navigator.push<ConflictResolvedResult>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MergePickerScreen(
                                  repo: widget.repo,
                                  entry: entry,
                                  myDeviceName: _myDeviceName,
                                ),
                              ),
                            );
                            if (result?.resolved == true && context.mounted) {
                              Navigator.pop(context, result);
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: kTextMid),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            minimumSize: const Size.fromHeight(0),
                          ),
                          child: Text('MERGE PIECES INSTEAD',
                              style: TextStyle(
                                  color: kTextMid,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3)),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.info_outline,
                            color: kTextDim, size: 20),
                        tooltip: 'What is this?',
                        onPressed: () => _showInfo(
                          'Merge pieces instead',
                          'Pick individual sentences from each side to '
                              'hand-build your own combined version - '
                              'more control, more work than Keep both. '
                              'A paid feature.\n\nYou choose exactly what '
                              'stays and what goes, piece by piece, '
                              'instead of keeping both sides whole.',
                        ),
                      ),
                    ],
                  ),
                ] else
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
                const SizedBox(height: 14),
                // 2026-09-07: real feedback, live - "the app is supposed
                // to fix" the common real case where neither version is
                // wrong, they're just two separate things that both
                // belong (this user's real example: two different
                // journal entries landing as one conflict). Not gated by
                // useDiff/version count like the two options above -
                // this works for any number of stacked versions, Kanban
                // or not. See _confirmAndKeepBoth/mergeConflictKeepingBoth.
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _confirmAndKeepBoth,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: kGreen),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          minimumSize: const Size.fromHeight(0),
                        ),
                        child: Text('KEEP BOTH',
                            style: TextStyle(
                                color: kGreen,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3)),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.info_outline, color: kTextDim, size: 20),
                      tooltip: 'What is this?',
                      // 2026-09-07: real feedback, live - "still too
                      // afraid to tap KEEP BOTH. The info needs clear
                      // non verbose text... that it's reversible or an
                      // undo or it's backed up and a link to the
                      // backup." Was one wordy paragraph about ordering
                      // logic with no mention of safety at all -
                      // replaced with the same short icon+point list the
                      // confirm dialog already uses, safety facts first.
                      onPressed: () => _showKeepBothInfo(),
                    ),
                  ],
                ),
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
    super.key,
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
