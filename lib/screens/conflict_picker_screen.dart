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

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../models/repository.dart';
import '../services/purchase_service.dart';
import '../services/conflict_repair.dart'
    show
        allHaveLeadingTime,
        findDuplicateParagraph,
        hasDuplicateParagraph,
        oneContainsTheOther,
        oneSideSuspiciouslyShort;
import '../services/conflict_scanner.dart';
import '../services/database_service.dart';
import '../services/device_name.dart';
import '../services/ios_app_service.dart';
import '../services/line_diff.dart' show mergeHunks;
import '../services/resolved_watchlist.dart';
import '../services/vault_folder_service.dart';
import '../services/word_diff.dart';
import 'backup_compare_screen.dart';
import 'merge_picker_screen.dart';
import 'paywall_keep_both_cleanup_screen.dart';
import '../services/localsync_folder.dart';

// 2026-08-18: "red colour more difficult than green below with same
// text size" - Material's default Colors.redAccent is noticeably
// lower-contrast against a dark background than kGreen's neon punch.
// A brighter, more saturated red reads at the same perceptual loudness.
const _kBrightRed = Color(0xFFFF3B30);

typedef ConflictResolvedResult = ({
  bool resolved,
  String? vaultName,
  String? backupRelPath,
  // 2026-09-08: real feedback, live - "confusing, build an easier
  // understanding." The permanent Undo (Conflicts screen -> Merged
  // conflicts) was real but hard to find - nothing pointed at it in
  // the moment. Non-null only for a Keep Both result, so the caller
  // can offer an immediate UNDO right on the success message itself -
  // zero navigation, no screen to go hunt for - while the permanent
  // path still exists underneath for later.
  KeptBothEntry? keptBoth,
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
  // 2026-09-14: real feedback, live - "I've said all along to include
  // all the text." The panels below only ever showed the disputed
  // span itself (versions[i].body) - correct for what actually needs a
  // decision, but it meant anything written earlier in the same note
  // (the rest of that day's journal entry, in the real case that
  // prompted this) was invisible here even though it's identical on
  // both devices and gives real context for judging the conflict.
  // Loaded once, read-only, never re-fetched - this screen never edits
  // anything outside the conflict span itself, so a stale copy here
  // has no consequence beyond a possibly-outdated context view (the
  // same file-changed-since-scan risk resolveConflict already guards
  // against for the part that actually gets written).
  String? _precedingContext;
  bool _contextLoadFailed = false;
  // 2026-09-14: real feedback, live - "the text for 0953 isn't on same
  // levels. Vimdiff would add auto spacing there so that the duplicate
  // text would be on the same lines." Both panels now split the shared
  // context at the identical point (previous fix), but the disputed
  // text itself is rarely the same length on both sides - one panel's
  // highlighted middle can wrap to several lines while the other's is
  // one short line, which pushes the shared text below it down by a
  // different amount on each side even though the text is identical.
  // Real vimdiff/side-by-side diff tools pad the shorter side with
  // blank space to compensate - can't compute that padding up front in
  // Flutter (wrapped height depends on the actual device's width, not
  // known until a real layout pass happens), so this measures both
  // disputed-text blocks after they first render, then pads the
  // shorter one to match. GlobalKeys read real RenderBox sizes after
  // layout; the padding fields feed back into a second, final build.
  final _leftDisputedKey = GlobalKey();
  final _rightDisputedKey = GlobalKey();
  double _leftExtraPad = 0;
  double _rightExtraPad = 0;
  // 2026-09-16: real feedback, live, real device - same measure-and-pad
  // idea as the disputed-text pair above, one row higher: the header
  // (device name + save time) can wrap to 2 lines on one side and stay
  // 1 line on the other, which used to push that side's diff content
  // down without moving the other side's, breaking row alignment
  // between panels from the very first line.
  final _leftHeaderKey = GlobalKey();
  final _rightHeaderKey = GlobalKey();
  double _leftHeaderExtraPad = 0;
  double _rightHeaderExtraPad = 0;

  @override
  void initState() {
    super.initState();
    _resolveMyDeviceName();
    _loadKeepLeftoverSetting();
    _loadPrecedingContext();
  }

  void _equalizeDisputedHeights() {
    final leftBox =
        _leftDisputedKey.currentContext?.findRenderObject() as RenderBox?;
    final rightBox =
        _rightDisputedKey.currentContext?.findRenderObject() as RenderBox?;
    if (leftBox == null || rightBox == null) return;
    final leftHeight = leftBox.size.height;
    final rightHeight = rightBox.size.height;
    final newLeftPad =
        rightHeight > leftHeight ? rightHeight - leftHeight : 0.0;
    final newRightPad =
        leftHeight > rightHeight ? leftHeight - rightHeight : 0.0;
    // Guard against an infinite measure->pad->remeasure loop - only
    // rebuild when the computed padding actually changed, and only by
    // more than a fraction of a pixel (adding padding itself changes
    // this widget's own height by exactly that padding, but never the
    // OTHER side's, so this settles after one correction, not never).
    final leftHeaderBox =
        _leftHeaderKey.currentContext?.findRenderObject() as RenderBox?;
    final rightHeaderBox =
        _rightHeaderKey.currentContext?.findRenderObject() as RenderBox?;
    double newLeftHeaderPad = _leftHeaderExtraPad;
    double newRightHeaderPad = _rightHeaderExtraPad;
    if (leftHeaderBox != null && rightHeaderBox != null) {
      final leftHeaderHeight = leftHeaderBox.size.height;
      final rightHeaderHeight = rightHeaderBox.size.height;
      newLeftHeaderPad = rightHeaderHeight > leftHeaderHeight
          ? rightHeaderHeight - leftHeaderHeight
          : 0.0;
      newRightHeaderPad = leftHeaderHeight > rightHeaderHeight
          ? leftHeaderHeight - rightHeaderHeight
          : 0.0;
    }
    if ((newLeftPad - _leftExtraPad).abs() > 0.5 ||
        (newRightPad - _rightExtraPad).abs() > 0.5 ||
        (newLeftHeaderPad - _leftHeaderExtraPad).abs() > 0.5 ||
        (newRightHeaderPad - _rightHeaderExtraPad).abs() > 0.5) {
      setState(() {
        _leftExtraPad = newLeftPad;
        _rightExtraPad = newRightPad;
        _leftHeaderExtraPad = newLeftHeaderPad;
        _rightHeaderExtraPad = newRightHeaderPad;
      });
    }
  }

  Future<void> _loadKeepLeftoverSetting() async {
    final value = await DatabaseService().getKeepLeftoverInNote();
    if (mounted) setState(() => _keepLeftoverInNote = value);
  }

  Future<void> _loadPrecedingContext() async {
    final vaultFolder = VaultFolderService();
    String? vaultPath;
    try {
      vaultPath = await vaultFolder.startAccessing(widget.repo.vaultBookmark);
      if (vaultPath == null) {
        if (mounted) setState(() => _contextLoadFailed = true);
        return;
      }
      final entry = widget.entry;
      final file = File('$vaultPath/${entry.filePath}');
      final content = await file.readAsString();
      if (entry.matchStart > content.length) {
        if (mounted) setState(() => _contextLoadFailed = true);
        return;
      }
      final preceding = content.substring(0, entry.matchStart).trimRight();
      if (mounted) setState(() => _precedingContext = preceding);
    } catch (_) {
      if (mounted) setState(() => _contextLoadFailed = true);
    } finally {
      if (vaultPath != null) {
        await vaultFolder.stopAccessing(widget.repo.vaultBookmark);
      }
    }
  }

  // 2026-09-08, fourth pass - real feedback, live: "the order is
  // different... these can be made consistent." This info popup and
  // _confirmAndKeepBoth's own confirm dialog covered the same 4-5
  // facts but drifted apart in both wording and order across earlier
  // passes, since each dialog was edited independently. One shared
  // list, built once, used by both call sites below - can't drift
  // apart again because there's only one copy to edit.
  // 2026-09-08, sixth pass - real feedback, live: "use my text and
  // order." Order now matches exactly the sequence given (undo,
  // backup, sort, both-kept, visible), not the earlier canonical
  // order this file had settled on before.
  List<Widget> _keepBothDialogPoints() {
    return [
      _DialogPoint(
        icon: Icons.undo,
        color: kGreen,
        text: 'UNDO button appears right after, on the confirmation '
            'message',
      ),
      // 2026-09-08, seventh pass - real feedback, live: "image cannot
      // be cloud as the privacy app is anti cloud... maybe a double
      // tick, but must be a different double tick to the below double
      // tick." Icons.backup is literally a cloud-with-upload-arrow
      // glyph in Material Design - a real contradiction for an app
      // whose entire promise is never touching a server. Went through
      // verified (single badge) first, corrected - library_add_check
      // (stacked pages + a check) reads as "multiple copies,
      // confirmed," genuinely distinct from done_all's plain
      // side-by-side ticks below.
      _DialogPoint(
        icon: Icons.library_add_check,
        color: kGreen,
        text: 'Backs up all text first, in ',
        linkText: '${lastKnownLocalSyncFolder}/Conflict Backups',
        onLinkTap: () =>
            IosAppServiceImpl().openObsidian(vaultName: widget.repo.name),
      ),
      // 2026-09-16: real feedback, live - "keeping both is a
      // concatenate dump." Rewritten to say plainly what this free
      // action actually does (whole-block concatenate, only reordered
      // if EACH side's own text starts with a clock time) rather than
      // "sorted by time," which reads as more thorough than it is -
      // see KEEP BOTH & CLEAN UP below for the real per-entry sort.
      _DialogPoint(
        icon: Icons.sort,
        color: kGreen,
        // 2026-09-18: real feedback, live - "not reordered entry by
        // entry. Just, not reordered." simplified per direct wording.
        text: 'Both texts kept as one block each, in time order if both '
            'start with a clock time HHMM - not reordered '
            '(see KEEP BOTH & CLEAN UP for that)',
      ),
      // 2026-09-08, fifth pass - real feedback, live: icon review.
      // done_all (two checks) reads as "both/every version," distinct
      // from the single-check "verified" badge above - the two were
      // easy to confuse as "the same tick" before.
      _DialogPoint(
        icon: Icons.done_all,
        color: kGreen,
        text: 'Both texts kept, as plain text',
      ),
      _DialogPoint(
        icon: Icons.visibility,
        color: kGreen,
        text: 'Text visible, all kept as plain text paragraphs, nothing '
            'hidden',
      ),
    ];
  }

  // 2026-09-08: real feedback, live - "fairly similar to the conflict
  // in question, what is the benefit?... verbose, maybe add points."
  // The picking UI genuinely is the same side-by-side diff view - the
  // real difference is time range: this works on any backup ever
  // saved, including long after a conflict's already been resolved,
  // not just the one active conflict this screen is already showing.
  void _showCompareBackupInfo() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kSurface,
        title: Text('Compare with a backup',
            style: TextStyle(color: kStar, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DialogPoint(
              icon: Icons.history,
              color: kGreen,
              text: 'Looks back further - every backup ever saved for '
                  'this note, not just this one conflict',
            ),
            _DialogPoint(
              icon: Icons.difference_outlined,
              color: kGreen,
              text: 'Same side-by-side diff view as above, so '
                  'differences are easy to spot',
            ),
            _DialogPoint(
              icon: Icons.restore,
              color: kGreen,
              text: 'Works anytime - even long after a conflict is '
                  'already resolved',
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

  // 2026-09-10: real feedback, live - "eye bleed, kiss, point form with
  // images" on the old one-paragraph _showInfo() version of this dialog.
  // Same _DialogPoint pattern as _keepBothDialogPoints below, which the
  // user confirmed is already good as-is.
  void _showMergeInfo() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kSurface,
        title: Text('Merge text instead',
            style: TextStyle(color: kStar, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DialogPoint(
              icon: Icons.checklist,
              color: kGreen,
              text: 'Pick individual sentences from each side to build '
                  'your own text',
            ),
            _DialogPoint(
              icon: Icons.tune,
              color: kGreen,
              text: 'More control than Keep Both, but more work',
            ),
            _DialogPoint(
              icon: Icons.lock,
              color: kGreen,
              text: 'A paid feature',
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

  // 2026-09-15: real feedback, live - "I see nothing about the hidden
  // meanings of coloured text... too dark and small to read and too
  // easy to overlook. This can be a large text in an i for info
  // section, with images and colours, less verbose, more imagery."
  // Same _DialogPoint pattern as the other info dialogs on this screen
  // (icon + 15px text, not a small dim caption) - reached from the "i"
  // next to "Tap to keep text you prefer" above.
  void _showDiffColorInfo() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kSurface,
        title: Text('Colours?',
            style: TextStyle(color: kStar, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 2026-09-15: real feedback, live - "red means danger, but
            // both sides are acceptable" - panels are green/blue now,
            // not red/green (see the two _ConflictPanel highlightColor
            // sites above), so these examples match. Both highlighted
            // lines say the exact same thing, just recolored - neither
            // side reads as the "bad" one. "Not sure which to pick?" is
            // white/neutral, not tied to either panel's color, since
            // it isn't about either specific side.
            _DialogPoint(
              icon: Icons.notes,
              color: kTextDim,
              textColor: kTextDim,
              text: 'Dimmed text - the same on every version, nothing '
                  'to decide here',
            ),
            // 2026-09-15: real feedback, live, several rounds - "so
            // explain what white means" then "White is plain text left
            // when nothing is flagged" then "if white is identical on
            // both sides, why isn't it grey?" (grey is OUTSIDE the
            // disputed paragraph, white is INSIDE it) then "white
            // should be flagged though, it's not synced on both sides"
            // - traced against the real Sep 7th note and that one was
            // right: the duplicate-highlighter panel's YouTube URL,
            // genuinely one-sided, rendered the same plain white as
            // shared text, because that panel wasn't running word-diff
            // at all. Fixed in code (disputedText() now combines
            // duplicate-highlighting with word-diff instead of one
            // replacing the other) rather than reworded again - white
            // now means what it always should have: this exact bit
            // exists on both sides, checked directly against the
            // other side's real text, in every mode.
            _DialogPoint(
              icon: Icons.text_fields,
              color: kStar,
              textColor: kStar,
              text: 'White text - on both versions. Nothing to decide '
                  'here, but read it for context',
            ),
            _DialogPoint(
              icon: Icons.highlight,
              color: kGreen,
              highlightBackground: kGreen.withValues(alpha: 0.28),
              text: 'Highlighted text - only on THAT version. Read it '
                  'before you choose',
            ),
            _DialogPoint(
              icon: Icons.highlight,
              color: kBlue,
              highlightBackground: kBlue.withValues(alpha: 0.28),
              text: 'Highlighted text - only on THAT version. Read it '
                  'before you choose',
            ),
            _DialogPoint(
              icon: Icons.warning_amber,
              color: Colors.amber,
              highlightBackground: Colors.amber.withValues(alpha: 0.35),
              text: 'Amber note - a heads-up worth reading before you '
                  'decide, like a repeated paragraph',
            ),
            // 2026-09-16: real feedback, live - real Sep 6th note: a
            // device's timestamp read "202609071425" on a note dated
            // Sep 6th - looked like a mismatch. It isn't: the timestamp
            // is when that edit was saved (labelForCommit's commit.time
            // in sync_service.dart), not the note's own date - writing
            // about yesterday a bit after midnight is normal. Concrete
            // real example instead of an abstract rule, per direct ask.
            _DialogPoint(
              icon: Icons.schedule,
              color: kTextDim,
              textColor: kTextDim,
              text: 'Real name: Journal/2026/09/Sep 6th, 2026.md\n'
                  'Merge name: desktop obsidian - 202609071425\n'
                  "Merge name's date is when that edit was saved",
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

  // 2026-09-07: real feedback, live - "still too afraid to tap KEEP
  // BOTH. The info needs clear non verbose text... that it's reversible
  // or an undo or it's backed up and a link to the backup, so it's easy
  // for a user to recover with little brain strain."
  void _showKeepBothInfo() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kSurface,
        title: Text('Keep both', style: TextStyle(color: kStar, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _keepBothDialogPoints(),
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
          // 2026-09-14: real feedback, live - "Keep this version? and
          // Keeps iPhone, change to 1 line Keeps iPhone." The title
          // asked a question the first content point immediately
          // answered - one line instead of two saying the same thing.
          title: Text('Keeps $label',
              style: TextStyle(color: kStar, fontSize: 17)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 2026-09-14: real feedback, live - "Move Every version
              // backed up first, to line 2." Reassurance now comes
              // right after what's kept, before the (by-default) loss
              // of the other side - so the safety net is read before
              // the thing it's a safety net FOR, not after.
              // 2026-09-14: real feedback, live - "Image is a cloud, but
              // no cloud. Use same backup image as Keep both versions?"
              // Icons.backup is the same cloud-with-upload-arrow glyph
              // already corrected for this exact reason in
              // _keepBothDialogPoints below - library_add_check matches
              // it here too.
              _DialogPoint(
                icon: Icons.library_add_check,
                color: kGreen,
                text: 'All text backed up first, in ',
                linkText: '${lastKnownLocalSyncFolder}/Conflict Backups',
                onLinkTap: () => IosAppServiceImpl()
                    .openObsidian(vaultName: widget.repo.name),
              ),
              // 2026-09-14: real feedback, live - "it doesn't make sense
              // holistically, with the other Keep this version points."
              // This used to be the one place stating the live
              // consequence, phrased two different ways depending on
              // the switch below - now a fixed statement of the
              // default (switch off), with the switch immediately
              // below it as the one place to change that, instead of
              // two texts trying to describe the same live state.
              _DialogPoint(
                  icon: Icons.cancel,
                  color: _kBrightRed,
                  text: otherCount == 1
                      ? 'Removes the other text from this note'
                      : 'Removes the other $otherCount texts from this note'),
              // 2026-09-08: real feedback, live - "gone entirely" (today)
              // vs "I need all or part of that data onto this device"
              // (2026-08-25's own explicit ask) are genuinely opposite
              // wants, not a bug to pick one winner for - a per-resolution
              // toggle right here beats a buried Settings-screen entry
              // nobody would find in the moment it actually matters.
              // Changing it here also updates the saved default via
              // DatabaseService, so the next resolution starts from
              // whatever was picked last.
              // 2026-09-14: real feedback, live - "I didn't realise
              // that's a real and live tick box... the image looks like
              // an svg graphic for a desktop or something." A checkbox
              // icon read as decorative, not an interactive control - a
              // real Switch is unambiguous, and its own on/off state is
              // now the only thing that needs to change (the red point
              // above states the default in fixed text; this row is the
              // one live control for it, with the switch itself showing
              // current state - no second text trying to track it).
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Switch(
                      value: _keepLeftoverInNote,
                      activeTrackColor: kGreen,
                      onChanged: (next) {
                        setDialogState(() {});
                        setState(() => _keepLeftoverInNote = next);
                        DatabaseService().setKeepLeftoverInNote(next);
                      },
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                          otherCount == 1
                              ? 'Keep the other text in this note '
                                  'too, collapsed for reference'
                              : 'Keep the other $otherCount texts '
                                  'in this note too, collapsed for '
                                  'reference',
                          style: TextStyle(color: kTextMid, fontSize: 13)),
                    ),
                  ],
                ),
              ),
              // 2026-09-14: real feedback, live - "Push after, then pull
              // on desktop... needs to be at the right position and
              // timing for the user... maybe the remember to push pull
              // needs to go here?" It used to sit as a static banner at
              // the bottom of the whole screen, shown before any choice
              // was even made - easy to have already scrolled past or
              // ignored by the time it actually mattered. This is the
              // literal moment it matters: the last thing shown before
              // the button that actually resolves it.
              const SizedBox(height: 4),
              _DialogPoint(
                icon: Icons.sync,
                color: kGreen,
                text: 'Push app after, then pull on desktop, for a full '
                    'sync',
              ),
            ],
          ),
          // 2026-09-14: real feedback, live - "Not now (is pushed to
          // right rather the left side) and Keep desktop obsidian -
          // 202609140910 (pushed to bottom left rather than being on
          // right side)." AlertDialog's default `actions` row
          // (OverflowBar) right-aligns two buttons on one line only
          // when they fit - $label can be long and dynamic (a real
          // device name plus a timestamp), and once it doesn't fit,
          // OverflowBar's own wrap behavior stacks and reorders both
          // buttons unpredictably rather than just wrapping the text
          // within a button. Explicit full-width stacked buttons
          // instead - same position every time regardless of how long
          // $label happens to be, matching this screen's own established
          // full-width OutlinedButton pattern (KEEP BOTH, MERGE TEXT
          // INSTEAD below).
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          actions: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: kGreen),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text('Keep $label',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: kStar, fontSize: 15)),
                ),
                const SizedBox(height: 8),
                // 2026-08-20: real feedback, live - kTextDim read as a
                // disabled/dead button, not a live but de-emphasized
                // one. kTextMid is still visibly secondary next to
                // "Keep $label"'s bright kStar, without looking inert.
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text('Not now',
                      style: TextStyle(color: kTextMid, fontSize: 15)),
                ),
              ],
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
          keptBoth: null,
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
        title: Text('Keep both texts?',
            style: TextStyle(color: kStar, fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _keepBothDialogPoints(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Not now',
                style: TextStyle(color: kTextMid, fontSize: 15)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child:
                Text('Keep both', style: TextStyle(color: kStar, fontSize: 15)),
          ),
        ],
      ),
    );
    if (proceed == true) await _keepBoth();
  }

  // 2026-09-16: Tier 3 IAP ("Keep Both & Clean Up" -
  // kKeepBothCleanupEntitlementId, purchase_service.dart) - real
  // feedback, live, on an actual conflict where both sides had
  // accumulated multiple timestamped entries each: "text with clock is
  // out of order on both desktop and phone" after running the free
  // KEEP BOTH. Same entitlement-check-then-paywall shape
  // sync_obsidian_preview_screen.dart already uses (skip the paywall
  // for anyone who already owns it, never re-charge).
  Future<void> _confirmAndKeepBothCleanedUp() async {
    final purchases = context.read<PurchaseService>();
    final alreadyOwned =
        await purchases.hasEntitlement(kKeepBothCleanupEntitlementId);
    if (!mounted) return;

    if (!alreadyOwned) {
      final unlocked = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) =>
                PaywallKeepBothCleanupScreen(purchases: purchases)),
      );
      if (unlocked != true || !mounted) return;
    }

    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kSurface,
        title: Text('Keep both texts, cleaned up?',
            style: TextStyle(color: kStar, fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ..._keepBothDialogPoints().take(2),
            _DialogPoint(
              icon: Icons.auto_fix_high,
              color: kGreen,
              text: 'Every timestamped entry from both sides, interleaved '
                  'by clock time - not just each side kept as one block',
            ),
            _DialogPoint(
              icon: Icons.done_all,
              color: kGreen,
              text: 'Both texts kept, as plain text',
            ),
            _DialogPoint(
              icon: Icons.visibility,
              color: kGreen,
              text: 'Text visible, all kept as plain text paragraphs, '
                  'nothing hidden',
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
            child:
                Text('Keep both', style: TextStyle(color: kStar, fontSize: 15)),
          ),
        ],
      ),
    );
    if (proceed == true) await _keepBoth(cleanUp: true);
  }

  Future<void> _keepBoth({bool cleanUp = false}) async {
    setState(() => _resolving = true);
    final vaultFolder = VaultFolderService();
    final path = await vaultFolder.startAccessing(widget.repo.vaultBookmark);
    String? backupRelPath;
    KeptBothEntry? keptBoth;
    try {
      if (path != null) {
        backupRelPath = await mergeConflictKeepingBoth(path, widget.entry,
            cleanUp: cleanUp);
        await DatabaseService().addResolvedRecords(
          recordsFor(widget.entry, DateTime.now()),
        );
        // 2026-09-08: real feedback, live - the permanent Undo (Merged
        // conflicts screen) existed but nobody could find it. Re-scans
        // for the marker mergeConflictKeepingBoth just wrote so the
        // caller can offer an immediate UNDO right on the success
        // message - same underlying undoKeepBoth, just surfaced where
        // it's actually useful: right after the action, not a
        // screen away.
        final freshlyKept = await scanForKeptBoth(path);
        keptBoth = freshlyKept
            .where((k) => k.filePath == widget.entry.filePath)
            .firstOrNull;
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
          keptBoth: keptBoth,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Re-measures after every build (cheap - two RenderBox reads, and
    // _equalizeDisputedHeights itself no-ops once the padding is
    // already correct) so a rotation, a font-size change, or the very
    // first frame all converge to matching heights without any extra
    // wiring at each individual call site that could rebuild this
    // screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _equalizeDisputedHeights();
    });
    final entry = widget.entry;
    // 2026-09-16: real feedback, live - "device based on left is common
    // sense for human UX. Left is first and of most importance and
    // convenience." Position used to just follow entry.versions' file
    // order (or, for two same-day journal entries, the chronological-
    // time write order from conflict_repair.dart's mergeBoth) with no
    // regard for which side is "yours" - same coincidence-only ordering
    // titleFor/colorFor already had to be fixed for on 2026-09-14/15.
    // Now the two-panel review always puts this device's own version on
    // the left, regardless of file or chronological order. That write-
    // time ordering is untouched and still governs Keep Both's merged
    // text and the raw file's own layout - only this screen's left/right
    // review position changes here.
    final rawVersions = entry.versions;
    final versions = rawVersions.length == 2 && rawVersions[1].who == 'yours'
        ? [rawVersions[1], rawVersions[0]]
        : rawVersions;
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

    // 2026-09-14: real feedback, live - "Desktop Sep 14 text now wrong
    // with 0953 before 0951 text... I'm confused, did I type the times
    // wrong?" Not a typing error - the picker briefly tried placing the
    // disputed text at its real chronological spot among the shared
    // context (a same-day fix, since reverted), but resolveConflict/
    // applyResolution (conflict_scanner.dart) only ever replaces the
    // conflict span in place - it never actually moves anything in the
    // file. The picker's smart-looking preview was promising a
    // reordering the write never delivered, leaving the resolved text
    // sitting wherever the conflict marker originally was (often the
    // end of the note) regardless of what time it claimed. Back to the
    // simple, honest version: shared context always shown after the
    // disputed text, matching exactly where resolving actually puts it.
    // 2026-09-15: real bug, confirmed against the actual file on disk
    // (real Sep 7th case: 1603 at line 1, 2105 - inside the conflict
    // block - at line 36) - _precedingContext is genuinely the text
    // BEFORE the conflict marker in the file, but it was wired into
    // afterContext, which _ConflictPanel renders AFTER the disputed
    // text. That put file-earlier, time-earlier content (1603) below
    // the disputed text (2105) instead of above it. beforeContext was
    // never anything but a hardcoded empty string - there is no
    // "following" context loaded anywhere in this screen, only
    // preceding, so it belongs in beforeContext, not afterContext.
    final sharedBeforeContext = _precedingContext ?? '';
    const sharedAfterContext = '';

    // 2026-09-14: real feedback, live - "the 2 sides don't correspond to
    // what I'm seeing on the desktop and phone versions." This used to
    // label index 0 as "This device" unconditionally - correct only by
    // coincidence when 'yours' happened to be the first callout written
    // to the file. Nothing guarantees that ordering (versions are built
    // in whatever order the callouts physically appear - see
    // conflict_scanner.dart's non-Kanban parsing loop), so a file where
    // the other device's edit landed first mislabeled it as this
    // device's own edit. Checks the actual who value instead of
    // position, so the label always matches the real data regardless of
    // file order.
    String titleFor(int i) {
      final v = versions[i];
      if (v.who == 'yours') {
        return _myDeviceName.isEmpty ? 'This device' : _myDeviceName;
      }
      return v.who;
    }

    // 2026-09-16: panel header - device name + save time combined, same
    // single-line format as before, just no longer truncated (see the
    // Text widget below). The Real name/Merge name distinction (this
    // vs. the note's own file path) is explained in the Colours? info
    // dialog instead of repeated on every panel - see _showDiffColorInfo.
    String mergeNameFor(int i) {
      final v = versions[i];
      final name = titleFor(i);
      return v.when != null ? '$name - ${v.when}' : name;
    }

    // 2026-09-15: real feedback, live - real Sep 6th note: "desktop
    // obsidian in green on the left and iPhone in blue on the right,
    // what's wrong?" Nothing crashing - titleFor above already solved
    // labeling correctly by identity (who == 'yours'), not position,
    // back on 2026-09-14 - but the PANEL COLORS were never given the
    // same fix, still hardcoded kGreen for index 0 / kBlue for index 1
    // regardless of which device that happened to be. Since versions'
    // array order is file-dependent, not device-dependent (same
    // 2026-09-14 finding), that meant green/blue tracked screen
    // position, not "this device" vs "desktop" - exactly backwards
    // from what "make iPhone green, desktop blue" (a few messages
    // earlier, on the Tap-to-keep caption) asked for. colorFor uses the
    // same identity check titleFor already does, so whichever index is
    // genuinely "yours" is green and the other is blue, regardless of
    // which side of the file/screen it lands on.
    Color colorFor(int i) => versions[i].who == 'yours' ? kGreen : kBlue;

    // 2026-09-08: real feedback, live - "fix the app as if a user
    // doesn't have access to Claude AI." Every real conflict this
    // session got resolved by reading the content and noticing each
    // side starts with a different bare clock time - a real signal
    // that these are two separate entries, not an actual edit
    // conflict. Surfaced directly so a user can make that call
    // themselves, without needing it read out loud to them.
    // 2026-09-08: real feedback, live - "go with both." Computed
    // before the two hints below so both can defer to it - a
    // suspiciously short side is a warning worth checking before
    // acting, not a reassurance, so it takes priority over both.
    final oneSideTooShort = versions.length == 2 &&
        oneSideSuspiciouslyShort(versions[0].body, versions[1].body);
    // 2026-09-14: real feedback, live - real case, Sep 12th conflict:
    // "1315 2 guys pushed in at different times..." (timed) vs.
    // "Obsidian desktop has about 10 sispnuits reminders, fix." (no
    // time at all) - two genuinely separate, unrelated notes, but this
    // hint never fired because it required EVERY side to carry a
    // leading time, not just one. A real edit of existing timestamped
    // prose essentially never strips the leading time entirely - one
    // side timed and the other with no time marker at all is itself a
    // safe, distinct signal these are different things, not a weaker
    // version of the "every side timed" case. Still purely advisory
    // (never says which one to keep, only that Keep Both is usually
    // right) - this widens WHEN the hint shows, not what it claims.
    final anyHasLeadingTime = versions.any((v) => allHaveLeadingTime([v.body]));
    final looksLikeSeparateEntries = !oneSideTooShort && anyHasLeadingTime;
    // 2026-09-08: real feedback, live - "that's a useful hint... more
    // of this." Second deterministic signal: one side's text fully
    // contains the other's, meaning nothing is actually lost by
    // keeping the longer one. Only checked pairwise (exactly 2
    // versions, same gate useDiff already uses) and only shown when
    // the time-based hint above doesn't already apply, so a note
    // never shows two competing suggestions at once.
    final oneSideHasEverything = !oneSideTooShort &&
        !looksLikeSeparateEntries &&
        versions.length == 2 &&
        oneContainsTheOther(versions[0].body, versions[1].body);
    // 2026-09-08, second pass - real feedback, live: "why isn't this
    // suggestion with a reason a hint on the app?" The first version
    // of this hint only named which side had a repeat - it stopped
    // short of the actual actionable reasoning (this session's own
    // real Sep 7th case: 'yours' repeats, 'desktop' doesn't, so
    // 'desktop' is the one to keep). Now checks that specifically -
    // exactly one side affected, not both - and recommends the clean
    // one by name when it can. Falls back to the neutral "worth
    // cleaning up" wording when both sides have the problem (nothing
    // to recommend) or when there are 3+ versions (which side is
    // "the other one" stops being a single, unambiguous answer).
    final duplicateSide =
        versions.indexWhere((v) => hasDuplicateParagraph(v.body));
    final onlyOneSideDuplicates = versions.length == 2 &&
        duplicateSide != -1 &&
        !hasDuplicateParagraph(versions[1 - duplicateSide].body);
    // 2026-09-15: real feedback, live - "colour the relevant text
    // orange... easy for the user's eye to see where the duplicate
    // text to delete is." The amber hint above named which side has a
    // repeat but never showed where in the text - this is passed to
    // that side's own _ConflictPanel so it can highlight both
    // occurrences directly.
    final duplicateParagraph =
        duplicateSide != -1 ? findDuplicateParagraph(versions[duplicateSide].body) : null;
    // 2026-09-08: real feedback, live - "does that really work?" It
    // didn't, for the case that matters most (two sides with nothing
    // in common - the real Sep 7th shape). mergeHunks collapses to one
    // all-or-nothing hunk when nothing aligns between the sides, same
    // limitation as picking a whole side - it only genuinely splits
    // into separate pickable pieces when there's some shared content
    // to anchor the alignment on. Checked for real (not assumed) so
    // Merge is only pointed at when it would actually help.
    final mergeWouldHelp = onlyOneSideDuplicates &&
        mergeHunks(versions[0].body, versions[1].body).length > 1;

    return Scaffold(
      // 2026-08-22: explicit kVoid removed - see settings_screen.dart's
      // matching comment. ThemeData.scaffoldBackgroundColor is now
      // transparent so the global FlagBackdrop shows through instead.
      appBar: AppBar(
        backgroundColor: kVoid,
        title:
            Text(entry.filePath, style: TextStyle(color: kStar, fontSize: 16)),
      ),
      body: _resolving
          ? Center(child: CircularProgressIndicator(color: kGreen))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 2026-09-14: real feedback, live - "I've said all along
                // to include all the fucking text", then "disjointed,
                // messy and confusing... why not have the text in the
                // left red or right green text?" A separate gray context
                // block above the two colored panels read as a third,
                // disconnected thing rather than part of either choice.
                // Folded into each panel instead (see _ConflictPanel's
                // leadingContext) - each one now reads as a real preview
                // of what the whole note looks like if that side is kept,
                // shared text muted, that side's own addition in its own
                // color, no separate block to reconcile against.
                if (_contextLoadFailed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber,
                            color: Colors.amber, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                              "Couldn't load the rest of this note for "
                              'context - the two versions below are still '
                              'complete and safe to decide from.',
                              style: TextStyle(
                                  color: Colors.amber,
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic)),
                        ),
                      ],
                    ),
                  ),
                // 2026-09-10: real feedback, live - "needs an image on
                // the left." touch_app matches the instruction itself
                // (tap a version below to act on it).
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(Icons.touch_app, color: kStar, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: versions.length > 2
                          ? Text(
                              "This note has ${versions.length} unresolved "
                              'versions stacked up - they were never '
                              'fully resolved before another change '
                              'arrived. Tap the one to keep; the rest '
                              'are still saved to "${lastKnownLocalSyncFolder}/Conflict Backups".',
                              style: TextStyle(color: kStar, fontSize: 15))
                          // 2026-09-14: real feedback, live, two
                          // rounds - first "I don't need to tap, as
                          // I already see, read and can review
                          // right now in this screen" (dropped the
                          // stale "review" framing), then "this
                          // text Keep this version must be the same
                          // as the Tap a version, then tap Keep
                          // this version, at the top" - the actual
                          // confirm button says "Keep this
                          // version" verbatim; this line described
                          // the same action in different words,
                          // which read as a mismatch rather than
                          // the same step. Now names the real
                          // button text directly.
                          // 2026-09-14: "this text and the Conflict
                          // text need to not be verbose."
                          // 2026-09-15: real feedback, live - "change
                          // to: Tap to keep iPhone or desktop obsidian
                          // - 202..." Names the actual two versions
                          // (titleFor already resolves each to a real
                          // device name or who/when) instead of the
                          // generic "text you prefer," so this line
                          // says exactly what's being chosen between.
                          // 2026-09-15, same day: "can you make iPhone
                          // green and desktop obsidian blue?" - each
                          // name now colored to match its own panel's
                          // highlightColor below, via colorFor(i) (by
                          // device identity, not panel position - see
                          // colorFor's own comment for why position
                          // alone got this backwards on a real note),
                          // so the caption itself previews which side is
                          // which before the panels are even read.
                          : Text.rich(
                              TextSpan(
                                style:
                                    TextStyle(color: kStar, fontSize: 15),
                                children: [
                                  const TextSpan(text: 'Tap to keep '),
                                  TextSpan(
                                      text: titleFor(0),
                                      style: TextStyle(
                                          color: colorFor(0),
                                          fontWeight: FontWeight.bold)),
                                  const TextSpan(text: ' or '),
                                  TextSpan(
                                      text: titleFor(1),
                                      style: TextStyle(
                                          color: colorFor(1),
                                          fontWeight: FontWeight.bold)),
                                  const TextSpan(text: '.'),
                                ],
                              ),
                            ),
                    ),
                    // 2026-09-15: real feedback, live - a small dimmed
                    // caption above the diff ("grey text too dark and
                    // small... too easy to overlook") failed exactly
                    // the way it was warned it might. Replaced with the
                    // same info-button pattern already proven readable
                    // elsewhere on this screen (Keep Both, Merge,
                    // Compare with a backup) - an icon here, a real
                    // dialog with big colored icon+text lines when
                    // tapped, not a caption easy to skim past.
                    // 2026-09-15: real feedback, live - "the i is lower
                    // than the line... stop wasting space." IconButton's
                    // default 48x48 minimum tap target was taller than
                    // this row's text, pushing its centered icon lower
                    // than the text above it and inflating the row's
                    // height for no reason. Zero padding + tight
                    // constraints makes it exactly icon-sized, same as
                    // every other inline element in this row.
                    IconButton(
                      icon: Icon(Icons.info_outline, color: kTextDim, size: 20),
                      tooltip: 'Colours?',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _showDiffColorInfo(),
                    ),
                  ],
                ),
                // 2026-09-15: real feedback, live - "Move Unsure? text to
                // under the Tap to keep text you prefer and above tips
                // that appear in Conflicts." Used to sit directly under
                // the KEEP BOTH button further down; now it's the first
                // thing read after the tap instruction, before any of
                // the conflict-shape-specific hints below.
                // 2026-09-16: real feedback, live - "tip 1 is permanent
                // right? Maybe just have a white light bulb and no
                // KWORLD AUTO TIP." Unlike the two hints below, this one
                // always shows regardless of conflict shape - the
                // KWORLD AUTO TIP branding is for the ones that actually
                // auto-detect something, not this static instruction.
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lightbulb_outline, color: Colors.white, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                            'Unsure? KEEP BOTH never loses data - worst '
                            'case, delete a duplicate line after.',
                            style: TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
                if (oneSideTooShort) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber, color: Colors.amber, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Check it\'s not an accidental empty edit '
                          'before choosing it - one side is much '
                          'shorter than the other.',
                          style: TextStyle(
                              color: Colors.amber,
                              fontSize: 13,
                              fontStyle: FontStyle.italic),
                        ),
                      ),
                    ],
                  ),
                ],
                if (looksLikeSeparateEntries) ...[
                  const SizedBox(height: 8),
                  _autoTipRow(
                      kGreen,
                      allHaveLeadingTime(
                              versions.map((v) => v.body).toList())
                          ? '"KEEP BOTH" is usually right here\n'
                              '- each side starts with a different '
                              'clock time, these look like two '
                              'separate entries, not the same thing '
                              'edited twice.'
                          : '"KEEP BOTH" is usually right here\n'
                              '- one side has a clock time, the other '
                              'has none at all, these look like two '
                              'separate entries, not the same thing '
                              'edited twice.'),
                ],
                if (oneSideHasEverything) ...[
                  const SizedBox(height: 8),
                  _autoTipRow(
                      kGreen,
                      'Keeping the longer version loses nothing - '
                      'it already contains all of the other\'s '
                      'text, plus more.'),
                ],
                if (duplicateSide != -1) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber, color: Colors.amber, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          !onlyOneSideDuplicates
                              ? 'Worth cleaning up after you resolve this '
                                  '- "${titleFor(duplicateSide)}" repeats '
                                  'the same paragraph twice.'
                              : mergeWouldHelp
                                  ? '"Merge text instead" below can keep '
                                      'one copy plus everything from the '
                                      'other side.\n"${titleFor(duplicateSide)}" '
                                      '(${duplicateSide == 0 ? 'left' : 'right'}) '
                                      'repeats the same paragraph twice, '
                                      '"${titleFor(1 - duplicateSide)}" '
                                      'doesn\'t have that problem.'
                                  : 'KEEP BOTH, then manually delete the '
                                      'extra copy after\n- picking a side '
                                      'would drop whatever unique text is '
                                      'on the other one.\n"${titleFor(duplicateSide)}" '
                                      '(${duplicateSide == 0 ? 'left' : 'right'}) '
                                      'repeats the same paragraph twice, '
                                      '"${titleFor(1 - duplicateSide)}" '
                                      'doesn\'t have that problem, and the '
                                      'two sides share nothing else in '
                                      'common.',
                          style: TextStyle(
                              color: Colors.amber,
                              fontSize: 13,
                              fontStyle: FontStyle.italic),
                        ),
                      ),
                    ],
                  ),
                ],
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
                // 2026-09-15: real feedback, live - "Controls at top
                // rather than bottom where they're unseen and hard to
                // find. MERGE TEXT INSTEAD KEEP BOTH to be above text."
                // Both action buttons used to sit below the diff
                // panels/stacked text, which can run long - moved above
                // so they're visible without scrolling past whatever
                // text happens to be in this conflict. Panels/text stay
                // below, still tappable to pick a version directly.
                // 2026-09-15: real feedback, live - "Move KEEP BOTH
                // above and it's text below: Unsure?... then push."
                // KEEP BOTH used to sit below MERGE TEXT INSTEAD with
                // no real reasoning behind that order - just an
                // artifact of an earlier "controls above the text"
                // request that happened to list them in that sequence.
                // Given this app's own top priority is never losing
                // data (see feedback_never_lose_data_priority memory),
                // the safe default belongs on top. Not gated by
                // useDiff/version count like MERGE below - this works
                // for any number of stacked versions, Kanban or not.
                // See _confirmAndKeepBoth/mergeConflictKeepingBoth.
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _confirmAndKeepBoth,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: kStar),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          minimumSize: const Size.fromHeight(0),
                        ),
                        // 2026-09-10: real feedback, live - "needs images
                        // to the left." Same glyph _keepBothDialogPoints
                        // already uses for "both kept," reused here.
                        // 2026-09-15: real feedback, live - "KEEP BOTH
                        // button to be white" - kGreen matched the
                        // adjacent Unsure? tip when that tip sat directly
                        // under this button; now that the tip moved up
                        // near the top of the screen (see above), kStar
                        // keeps this button visually consistent with the
                        // now-white MERGE TEXT INSTEAD button below it.
                        icon: Icon(Icons.done_all, color: kStar, size: 18),
                        label: Text('KEEP BOTH',
                            style: TextStyle(
                                color: kStar,
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
                // 2026-09-16: Tier 3 IAP - real feedback, live, on an
                // actual conflict where both sides had accumulated
                // multiple timestamped entries each: "text with clock
                // is out of order on both desktop and phone" after
                // running the free KEEP BOTH above (a plain
                // concatenate, honestly described as such now - see
                // _keepBothDialogPoints). This does the real
                // per-entry chronological interleave instead
                // (journalOrderedEntries) - see
                // _confirmAndKeepBothCleanedUp.
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _confirmAndKeepBothCleanedUp,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: kGreen),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          minimumSize: const Size.fromHeight(0),
                        ),
                        icon: Icon(Icons.auto_fix_high, color: kGreen, size: 18),
                        label: Text('KEEP BOTH & CLEAN UP',
                            style: TextStyle(
                                color: kGreen,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3)),
                      ),
                    ),
                  ],
                ),
                if (useDiff && versions.length == 2) ...[
                  const SizedBox(height: 10),
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
                        child: OutlinedButton.icon(
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
                            side: BorderSide(color: kStar),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            minimumSize: const Size.fromHeight(0),
                          ),
                          // 2026-09-10: real feedback, live - "needs
                          // images to the left of them" (both buttons).
                          // 2026-09-15: real feedback, live - "grey
                          // looks like a dead button." kTextMid is
                          // deliberately low-contrast everywhere else
                          // on this screen (it's the de-emphasized-text
                          // color), so a real, always-tappable button
                          // in that same color read as disabled. Tried
                          // kBlue next (already an active color on this
                          // screen), but "is this related to the left
                          // iPhone green and right desktop blue?" was a
                          // fair catch - kBlue is used almost nowhere
                          // else on this screen except as the right/
                          // desktop panel's own color (kGreen, by
                          // contrast, is this whole screen's generic
                          // accent - tips, checkmarks, the shield icon -
                          // not specifically the left panel, so KEEP
                          // BOTH's green isn't the same risk). kStar is
                          // neutral: bright enough to read as live, not
                          // borrowed from either side's identity.
                          icon: Icon(Icons.merge, color: kStar, size: 18),
                          label: Text('MERGE TEXT INSTEAD',
                              style: TextStyle(
                                  color: kStar,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3)),
                        ),
                      ),
                      IconButton(
                        icon:
                            Icon(Icons.info_outline, color: kTextDim, size: 20),
                        tooltip: 'What is this?',
                        // 2026-09-10: real feedback, live - "eye bleed,
                        // kiss, point form with images" - was one dense
                        // paragraph, same fix already applied to the Keep
                        // Both dialog below (_keepBothDialogPoints):
                        // short icon+label lines instead of prose.
                        onPressed: () => _showMergeInfo(),
                      ),
                    ],
                  ),
                ],
                // 2026-09-15: real feedback, live - "Move Compare with a
                // backup under MERGE TEXT INSTEAD." Previously sat right
                // under the Unsure? tip, back when that tip was still
                // directly below KEEP BOTH - now that the tip moved up
                // near the top of the screen, this follows the last
                // action button instead.
                const SizedBox(height: 8),
                // 2026-09-15: real feedback, live - "right align this, so
                // the i for info will be in line with the 3 above i's."
                // mainAxisSize.min on this Row (and its InkWell's own
                // inner min-sized Row) hugged the info button right up
                // against the text instead of pushing it to the row's
                // far right edge - the other three info buttons above
                // (Tap to keep, KEEP BOTH, MERGE TEXT INSTEAD) all sit at
                // the right edge because their own leading content is
                // wrapped in Expanded. Same fix here.
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
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
                          // 2026-09-15: real feedback, live - "you forgot
                          // to move the text Compare with a backup, to
                          // the right as well." The outer Expanded only
                          // pushed the trailing info button to the row's
                          // right edge - this inner Row's own content
                          // still defaulted to hugging its own left edge
                          // inside that Expanded space. end pulls the
                          // icon+text over too, so the whole link sits
                          // right next to the info button, not stranded
                          // on the left with empty space in between.
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
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
                    ),
                    // 2026-09-08: real feedback, live - "what does this
                    // do, I need an i for information." Same pattern
                    // as the other two info buttons on this screen.
                    IconButton(
                      icon: Icon(Icons.info_outline, color: kTextDim, size: 18),
                      tooltip: 'What is this?',
                      onPressed: _showCompareBackupInfo,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (useDiff && versions.length == 2) ...[
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _ConflictPanel(
                            title: mergeNameFor(0),
                            tokens: wordDiffOurs(
                                versions[0].body, versions[1].body),
                            plainText: versions[0].body,
                            // 2026-09-15: real feedback, live - "red
                            // means danger, but both sides are
                            // acceptable." Red implied one side was the
                            // wrong/bad choice - neither is, it's just
                            // the other version. Green/blue instead.
                            // 2026-09-15, later same day: colorFor, not
                            // a bare kGreen - see colorFor's own comment
                            // above for why hardcoding by index instead
                            // of identity put desktop in green on a real
                            // note where it happened to load first.
                            highlightColor: colorFor(0),
                            duplicateParagraph:
                                duplicateSide == 0 ? duplicateParagraph : null,
                            beforeContext: sharedBeforeContext,
                            afterContext: sharedAfterContext,
                            disputedKey: _leftDisputedKey,
                            extraPadBelowDisputed: _leftExtraPad,
                            headerKey: _leftHeaderKey,
                            extraPadBelowHeader: _leftHeaderExtraPad,
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
                            title: mergeNameFor(1),
                            tokens: wordDiffTheirs(
                                versions[0].body, versions[1].body),
                            plainText: versions[1].body,
                            highlightColor: colorFor(1),
                            duplicateParagraph:
                                duplicateSide == 1 ? duplicateParagraph : null,
                            beforeContext: sharedBeforeContext,
                            afterContext: sharedAfterContext,
                            disputedKey: _rightDisputedKey,
                            extraPadBelowDisputed: _rightExtraPad,
                            headerKey: _rightHeaderKey,
                            extraPadBelowHeader: _rightHeaderExtraPad,
                            onTap: () => _confirmAndChoose(
                                titleFor(1), versions[1].body),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else
                  for (var i = 0; i < versions.length; i++) ...[
                    if (i > 0) const SizedBox(height: 16),
                    _ConflictPanel(
                      title: mergeNameFor(i),
                      tokens: null,
                      plainText: versions[i].body,
                      highlightColor: colorFor(i),
                      duplicateParagraph:
                          i == duplicateSide ? duplicateParagraph : null,
                      beforeContext: sharedBeforeContext,
                      afterContext: sharedAfterContext,
                      onTap: () =>
                          _confirmAndChoose(titleFor(i), versions[i].body),
                    ),
                  ],
                // 2026-09-14: real feedback, live - "needs to be at the
                // right position and timing for the user... maybe the
                // remember to push pull needs to go here?" Moved into the
                // confirm dialog itself (_confirmAndChoose's own dialog,
                // above the checkbox), right before the button that
                // actually resolves it - closer to the real moment of
                // action than a static banner sitting here regardless of
                // whether any choice has been made yet.
              ],
            ),
    );
  }

  // 2026-09-16: real feedback, live - brand the auto-suggested hints on
  // this screen (KEEP BOTH etc.) as "KWORLD AUTO TIP" with a small KAT
  // (kworld auto tip) mark, instead of a bare Material icon - reusable
  // across other kworld.space apps later, not just this one.
  Widget _autoTipRow(Color color, String text, {double iconSize = 16}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SvgPicture.asset('assets/logos/kat_icon.svg',
            width: iconSize,
            height: iconSize,
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn)),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('KWORLD AUTO TIP',
                  style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8)),
              const SizedBox(height: 2),
              Text(text,
                  style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontStyle: FontStyle.italic)),
            ],
          ),
        ),
      ],
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
  // 2026-09-15: real feedback, live - the "What do the colors mean?"
  // dialog described dimmed/amber/highlighted text but every line's
  // own text still rendered in plain kStar white, contradicting the
  // point being made. null (every other call site) keeps the existing
  // kStar text - only _showDiffColorInfo passes a real value, since
  // that's the one dialog where the text itself needs to demonstrate
  // the color, not just the icon next to it.
  final Color? textColor;
  // 2026-09-15: real feedback, live - "the Tap to keep text you prefer
  // colour explainer compared to the [real Sep 7th] conflict... having
  // amber highlighted text, specifically #Tonight." The dialog was
  // previewing green/blue/amber as solid, full-opacity colored TEXT -
  // but _ConflictPanel never colors text itself for these three, it
  // puts plain white text on a translucent colored BACKGROUND (28%
  // for green/blue, 35% for amber - see highlightColor.withValues and
  // Colors.amber.withValues above). Solid amber text next to a
  // washed-out 35%-opacity chip don't look alike, which is exactly
  // what was being pointed at. Set for the three highlight entries
  // only - dimmed/white stay genuinely colored text with no
  // background, matching their own real usage.
  final Color? highlightBackground;
  const _DialogPoint({
    required this.icon,
    required this.color,
    required this.text,
    this.linkText,
    this.onLinkTap,
    this.textColor,
    this.highlightBackground,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedTextColor =
        highlightBackground != null ? kStar : (textColor ?? kStar);
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
                    style: TextStyle(
                        color: resolvedTextColor,
                        fontSize: 15,
                        backgroundColor: highlightBackground))
                : Text.rich(
                    TextSpan(
                      style: TextStyle(color: resolvedTextColor, fontSize: 15),
                      children: [
                        TextSpan(text: text),
                        TextSpan(
                          text: linkText,
                          style: TextStyle(
                            color: kGreen,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizer()..onTap = onLinkTap,
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
  // 2026-09-14: real feedback, live, two rounds - first "why not have
  // the text in the left red or right green text?" (folded a separate
  // gray block into each panel), then "the left and right sides need
  // to have the similar text on the same row, similar to vimdiff...
  // humans struggle to match the similar left and right text" (each
  // panel picking its own split point by its own disputed text's time
  // broke that alignment). Both beforeContext/afterContext are now
  // computed once by the parent screen, from whichever version
  // actually has a leading time, and passed down identically to every
  // panel - same shared text lands at the same row on every side,
  // only the highlighted middle (this panel's own disputed text)
  // differs. Empty strings (not null) when there's nothing on that
  // side - simpler than a nullable check at every call site.
  final String beforeContext;
  final String afterContext;
  // 2026-09-14: real feedback, live - "the text for 0953 isn't on same
  // levels. Vimdiff would add auto spacing there." disputedKey lets the
  // parent screen read this panel's real rendered height after layout
  // (see _ConflictPickerScreenState._equalizeDisputedHeights);
  // extraPadBelowDisputed is the gap it computed to insert on the
  // shorter side, so afterContext starts at the same row as the taller
  // side's. Both null/0 outside the side-by-side vimdiff layout (the
  // 3+-stacked-versions case has no "same row" to align against).
  final Key? disputedKey;
  final double extraPadBelowDisputed;
  // 2026-09-15: real feedback, live - "colour the relevant text
  // orange... easy for the user's eye to see where the duplicate text
  // to delete is." Set only for the panel whose own body actually
  // contains the repeat (see duplicateSide in the parent screen) - null
  // everywhere else, same as beforeContext/afterContext's empty-string
  // convention. Both occurrences get a background in Colors.amber -
  // 2026-09-15, real feedback, live: it used to be Colors.orange, a
  // different color to the "Amber note" dialog entry/warning icon
  // describing it despite both meaning the same thing - "they should
  // be the same fucking colour, the text description is exactly there
  // to explain the colours." Now literally the same Color value as the
  // warning icon/text below the panels.
  // 2026-09-15, same day, real bug found by tracing the actual Sep 7th
  // note: this used to lay the highlight over plain text INSTEAD of
  // the word-diff tokens, reasoning that "this paragraph repeats" and
  // "this word differs from the other side" would fight for the same
  // visual channel. That threw away real information - the panel's
  // own YouTube URL (never on the other side at all, genuinely
  // one-sided, needing to be synced) rendered identical plain white to
  // truly-shared text, because plain-text mode had no idea what the
  // other side even said. disputedText() now combines both: the amber
  // duplicate highlight wins where a span falls inside a duplicate
  // occurrence, green/blue still applies everywhere else a token is
  // one-sided - no channel conflict in practice since a token position
  // needs at most one of the two.
  final String? duplicateParagraph;
  // 2026-09-16: real feedback, live, real device - "Left column needs
  // text on same row as right column. Right column is pushed down with
  // full title name in blue correctly showing." The no-truncation fix
  // (title now wraps instead of ellipsis-cutting) can make one side's
  // header taller than the other's whenever one device name/timestamp
  // wraps to 2 lines and the other doesn't - same class of bug
  // disputedKey/extraPadBelowDisputed already solves below, just one
  // row higher up. Same exact pattern: headerKey lets the parent screen
  // measure this panel's real rendered header height after layout,
  // extraPadBelowHeader is the gap it computed to insert on the shorter
  // side so the diff content itself starts at the same row on both
  // sides, regardless of how many lines either title wrapped to.
  final Key? headerKey;
  final double extraPadBelowHeader;
  const _ConflictPanel({
    super.key,
    required this.title,
    required this.tokens,
    required this.plainText,
    required this.highlightColor,
    required this.onTap,
    this.beforeContext = '',
    this.afterContext = '',
    this.disputedKey,
    this.extraPadBelowDisputed = 0,
    this.duplicateParagraph,
    this.headerKey,
    this.extraPadBelowHeader = 0,
  });

  // 2026-09-15: real feedback, live - real Sep 7th case, traced: the
  // "yours" panel's YouTube URL (never present on the desktop side at
  // all) rendered plain white here, same as genuinely-shared text,
  // because plain-text substring highlighting had no idea what the
  // other side even said. "White text is text only on 1 side and
  // needing syncing, right?" - yes, for this exact gap: a one-sided
  // line could hide unflagged right next to an amber duplicate,
  // which is a real risk given this app's top priority is never
  // losing data (see feedback_never_lose_data_priority memory). Only
  // used when tokens == null (oversized fallback, no word-diff
  // available to combine with) - the normal case now goes through
  // _duplicateRanges + disputedText below instead.
  Widget _highlightDuplicate(String duplicate) {
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final idx = plainText.indexOf(duplicate, start);
      if (idx == -1) {
        spans.add(TextSpan(text: plainText.substring(start)));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: plainText.substring(start, idx)));
      }
      spans.add(TextSpan(
        text: duplicate,
        style: TextStyle(backgroundColor: Colors.amber.withValues(alpha: 0.35)),
      ));
      start = idx + duplicate.length;
    }
    return Text.rich(
      TextSpan(style: TextStyle(color: kStar, fontSize: 14), children: spans),
    );
  }

  // Every occurrence of [duplicate] within [plainText], as
  // [start, end) character ranges - tokens later look up their own
  // position against these instead of the color-vs-color conflict the
  // old single-mode split was trying to avoid (see duplicateParagraph's
  // own doc comment above, now outdated by this fix).
  List<(int, int)> _duplicateRanges(String duplicate) {
    final ranges = <(int, int)>[];
    var start = 0;
    while (true) {
      final idx = plainText.indexOf(duplicate, start);
      if (idx == -1) break;
      ranges.add((idx, idx + duplicate.length));
      start = idx + duplicate.length;
    }
    return ranges;
  }

  @override
  Widget build(BuildContext context) {
    Widget disputedText() {
      final duplicate = duplicateParagraph;
      if (tokens == null) {
        return duplicate != null && plainText.contains(duplicate)
            ? _highlightDuplicate(duplicate)
            : Text(plainText, style: TextStyle(color: kStar, fontSize: 14));
      }
      // Word-diff is available - combine it with the duplicate
      // highlight instead of one replacing the other, so a one-sided
      // line (like the real Sep 7th YouTube URL) still shows
      // green/blue even on the panel whose own text also happens to
      // repeat elsewhere. Concatenating tokens[].text in order
      // reconstructs plainText exactly (wordDiffOurs/wordDiffTheirs
      // guarantee this - see word_diff.dart), so a running offset is
      // enough to know each token's real position without re-deriving
      // it from the token text itself.
      final ranges = duplicate != null && plainText.contains(duplicate)
          ? _duplicateRanges(duplicate)
          : const <(int, int)>[];
      var offset = 0;
      return Text.rich(
        TextSpan(
          children: tokens!.map((t) {
            final mid = offset + t.text.length ~/ 2;
            offset += t.text.length;
            final inDuplicate = ranges.any((r) => mid >= r.$1 && mid < r.$2);
            return TextSpan(
              text: t.text,
              style: inDuplicate
                  ? TextStyle(
                      color: kStar,
                      fontSize: 14,
                      backgroundColor: Colors.amber.withValues(alpha: 0.35))
                  : t.op == DiffOp.equal
                      ? TextStyle(color: kStar, fontSize: 14)
                      : TextStyle(
                          color: kStar,
                          fontSize: 14,
                          backgroundColor: highlightColor.withValues(alpha: 0.28),
                        ),
            );
          }).toList(),
        ),
      );
    }

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
            // 2026-09-16: real feedback, live - "desktop obsidian -
            // 202... can you output the full text?" ellipsis truncated
            // the label to one line even though nothing below this
            // header needs the space - now wraps onto a second line
            // instead of cutting the timestamp off.
            Container(
                key: headerKey,
                child: Text(title,
                    style: TextStyle(
                        color: highlightColor,
                        fontSize: 14,
                        fontWeight: FontWeight.bold))),
            if (extraPadBelowHeader > 0) SizedBox(height: extraPadBelowHeader),
            const SizedBox(height: 6),
            // 2026-09-09: real feedback, live - "can't see all of the
            // text, which is cut off at the bottom and doesn't scroll."
            // The Column above had no scrollable ancestor at all -
            // long content simply overflowed past the panel's fixed
            // height with no way to read the rest. Expanded+
            // SingleChildScrollView lets it scroll within the panel's
            // own bounds instead.
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (beforeContext.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(beforeContext,
                            style: TextStyle(color: kTextDim, fontSize: 13)),
                      ),
                    Container(key: disputedKey, child: disputedText()),
                    if (extraPadBelowDisputed > 0)
                      SizedBox(height: extraPadBelowDisputed),
                    if (afterContext.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(afterContext,
                            style: TextStyle(color: kTextDim, fontSize: 13)),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
