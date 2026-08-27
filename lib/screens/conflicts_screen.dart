// screens/conflicts_screen.dart
//
// 2026-08-18: step 1 of the conflict-picker plan - see
// conflict_scanner.dart's header for why this is a live scan with no
// persisted state. This screen only lists what needs review and says
// where/who/when; tapping through to actually fix a file still happens
// in Obsidian by hand for now - the tap-to-pick resolution UI is the
// deliberately deferred step 2, once this list itself proves useful.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../models/repository.dart';
import '../services/conflict_scanner.dart';
import '../services/database_service.dart';
import '../services/ios_app_service.dart';
import '../services/resolved_watchlist.dart';
import '../services/vault_folder_service.dart';
import '../widgets/controllable_gif.dart';
import '../widgets/help_wizard.dart';
import 'conflict_picker_screen.dart';

// 2026-08-20: real feedback, live - after sorting most-recent-first, a
// brand-new conflict and a pile of unrelated older ones still look like
// one undifferentiated list, "eye bleed and brain stress." [when] is
// this app's own YYYYMMDDhhmm format everywhere else (see
// conflict_repair.dart's writer) - parsed by hand rather than pulling
// in a date-format string for one fixed, already-known shape.
DateTime? _parseWhen(String? when) {
  if (when == null || when.length != 12) return null;
  try {
    return DateTime(
      int.parse(when.substring(0, 4)),
      int.parse(when.substring(4, 6)),
      int.parse(when.substring(6, 8)),
      int.parse(when.substring(8, 10)),
      int.parse(when.substring(10, 12)),
    );
  } catch (_) {
    return null;
  }
}

class ConflictsScreen extends StatefulWidget {
  final Repository repo;
  const ConflictsScreen({super.key, required this.repo});

  @override
  State<ConflictsScreen> createState() => _ConflictsScreenState();
}

typedef _ScanResult = ({List<ConflictEntry> conflicts, List<ReferenceEntry> refs});

class _ConflictsScreenState extends State<ConflictsScreen> {
  final _vaultFolder = VaultFolderService();
  late Future<_ScanResult> _future;
  // 2026-08-20: filePaths of entries this scan found that match a
  // previously-resolved signature - see resolved_watchlist.dart. Keyed by
  // filePath rather than by entry identity since ConflictEntry has no id
  // of its own and filePath is unique enough for this app's one-conflict-
  // per-note-in-practice usage.
  Set<String> _revertedPaths = {};

  @override
  void initState() {
    super.initState();
    _future = _scan();
  }

  // 2026-08-26: real feedback, live - "the Conflicts page finished" -
  // scans both real unresolved conflicts and the "kept for reference"
  // leftovers (conflict_scanner.dart's scanForReferenceCallouts) in one
  // pass, so both sections refresh together off one future instead of
  // two independently-timed ones drifting apart.
  Future<_ScanResult> _scan() async {
    final path = await _vaultFolder.startAccessing(widget.repo.vaultBookmark);
    if (path == null) return (conflicts: <ConflictEntry>[], refs: <ReferenceEntry>[]);
    try {
      final entries = await scanForConflicts(path);
      // 2026-08-20: real device feedback, live - scanForConflicts returns
      // filesystem order, not recency, so a brand-new conflict can land
      // behind older accumulated ones in the list. That's exactly what
      // makes the auto-navigation into this screen feel like an ambush -
      // "shows a bunch of new data the user doesn't know about." Most
      // recent first means whatever the user just triggered is always
      // the first thing they see, not something they have to hunt for
      // past older, already-known entries. `when` is YYYYMMDDhhmm, so a
      // plain string compare already sorts chronologically; entries with
      // no timestamp (shouldn't normally happen - every stacked entry
      // has at least one non-"yours" version) sort last, not first.
      entries.sort((a, b) => (b.when ?? '').compareTo(a.when ?? ''));
      await _checkForReverts(entries);
      final refs = await scanForReferenceCallouts(path);
      return (conflicts: entries, refs: refs);
    } finally {
      await _vaultFolder.stopAccessing(widget.repo.vaultBookmark);
    }
  }

  /// Deletes one "kept for reference" leftover (always backed up first -
  /// see deleteReferenceCallout's own doc), then rescans both sections.
  Future<void> _deleteRef(ReferenceEntry ref) async {
    final path = await _vaultFolder.startAccessing(widget.repo.vaultBookmark);
    if (path == null) return;
    try {
      await deleteReferenceCallout(path, ref);
    } finally {
      await _vaultFolder.stopAccessing(widget.repo.vaultBookmark);
    }
    if (mounted) setState(() => _future = _scan());
  }

  /// Swaps a leftover reference callout back to being the kept content -
  /// see undoReferenceCallout's own doc (conflict_scanner.dart) for why
  /// this, unlike _deleteRef above, writes no extra backup first.
  Future<void> _undoRef(ReferenceEntry ref) async {
    final path = await _vaultFolder.startAccessing(widget.repo.vaultBookmark);
    if (path == null) return;
    try {
      await undoReferenceCallout(path, ref);
    } finally {
      await _vaultFolder.stopAccessing(widget.repo.vaultBookmark);
    }
    if (mounted) setState(() => _future = _scan());
  }

  Future<void> _checkForReverts(List<ConflictEntry> entries) async {
    final db = DatabaseService();
    final now = DateTime.now();
    final watchlist = pruneOld(await db.getResolvedWatchlist(), now);
    final reverted = findReverted(entries, watchlist);
    if (mounted) {
      setState(() => _revertedPaths = reverted.map((r) => r.filePath).toSet());
    }
    // Persist unconditionally: flushes both expired entries (already
    // dropped by pruneOld above) and matched ones (already done their
    // job - flagged once, no need to keep re-flagging every future scan
    // of the same file).
    final remaining = watchlist.where((r) => !reverted.any((m) =>
        m.filePath == r.filePath && m.who == r.who && m.when == r.when));
    await db.setResolvedWatchlist(remaining.toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 2026-08-22: explicit kVoid removed - see settings_screen.dart's
      // matching comment. ThemeData.scaffoldBackgroundColor is now
      // transparent so the global FlagBackdrop shows through instead.
      appBar: AppBar(
        backgroundColor: kVoid,
        title: Text('Conflicts', style: TextStyle(color: kStar)),
      ),
      body: Column(
        children: [
          // 2026-08-18: "too small and dark", "too verbose, create svg
          // images" - a full paragraph in dim small text asked the user
          // to read to feel reassured, the opposite of reassuring.
          // Built-in icons (not custom SVG - real rendering risk with
          // no way to preview them, per pairing_laptop_lock.svg's own
          // "took many iterations" history) walk the 3-step safety
          // story at a glance: conflict -> both saved -> pick anytime.
          // Full detail (exact folder name) stays one tap away via the
          // info button, not deleted - "Show details" is the same
          // pattern the sync-confirm dialog already uses.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: kSurface,
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      const _SafetyStep(
                        icon: Icons.compare_arrows,
                        label: 'Conflict',
                      ),
                      Icon(Icons.arrow_forward, color: kTextDim, size: 18),
                      const _SafetyStep(
                        icon: Icons.backup,
                        label: 'Both saved',
                      ),
                      Icon(Icons.arrow_forward, color: kTextDim, size: 18),
                      const _SafetyStep(
                        icon: Icons.touch_app,
                        label: 'Pick anytime',
                      ),
                      // 2026-08-26: real feedback, live - "I need this
                      // advice when using the app... here are the steps
                      // to sync after the conflict." Resolving a conflict
                      // only changes this device - the previous 3 steps
                      // stopped one step short of actually telling the
                      // user that, so real testing needed asking me
                      // directly for the missing step. Added here instead
                      // of only ever living in a chat answer.
                      Icon(Icons.arrow_forward, color: kTextDim, size: 18),
                      const _SafetyStep(
                        icon: Icons.cloud_upload,
                        label: 'Push to sync',
                      ),
                    ],
                  ),
                ),
                // 2026-08-27: replaced the static "How conflicts are kept
                // safe" info dialog with the branching help wizard
                // (help_wizard.dart, Flow B) - same icon and tap target,
                // real per-step guidance instead of one long paragraph.
                // The facts that dialog held (both versions always saved
                // first, LocalSync/Conflict Backups location, desktop
                // needs its own pull after push) aren't repeated 1:1 in
                // the wizard's terser cards - if real device testing
                // shows that's a gap, add it back as a card rather than
                // reviving the paragraph.
                // 2026-08-27: icon changed from info_outline to
                // help_outline - real feedback, live: Home's new icon and
                // this one were showing different glyphs (i vs ?) for the
                // exact same "opens the help wizard" action. Matching
                // Home's choice since this is genuinely guidance, not
                // static info.
                IconButton(
                  icon: Icon(Icons.help_outline, color: kTextMid),
                  tooltip: 'Help',
                  onPressed: () => showHelpWizard(context, 'B'),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<_ScanResult>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  // 2026-08-26: real feedback, live - "shows a circle
                  // activating, then No unresolved conflicts... add a
                  // text informing the user what's happening." A bare
                  // spinner with no label read as unclear/stuck, even
                  // though scanForConflicts (a recursive walk of every
                  // .md file) can take a moment on a large vault.
                  // 2026-08-26: real feedback, live - "can that change
                  // to the progress_dog.gif?" Same running-dog asset
                  // already used elsewhere for "something's happening"
                  // (linking_screen.dart/pairing_screen.dart) for visual
                  // consistency. ControllableGif directly, not the
                  // ActionGif/trigger wrapper those screens use - this
                  // isn't gesture-triggered, it just plays for exactly
                  // as long as the real scan takes (tied to playing:
                  // true for the whole time this branch is built), no
                  // swipe/floor-timing contract needed.
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const ControllableGif(
                          assetPath: 'assets/gifs/progress_running.gif',
                          playing: true,
                          height: 64,
                        ),
                        const SizedBox(height: 16),
                        Text('Scanning your entire phone PKM vault…',
                            style: TextStyle(color: kTextMid, fontSize: 14)),
                      ],
                    ),
                  );
                }
                final entries = snapshot.data?.conflicts ?? const [];
                final refs = snapshot.data?.refs ?? const [];
                if (entries.isEmpty && refs.isEmpty) {
                  // 2026-08-26: real feedback, live - "Conflicts screen
                  // makes no sense now" - a fixed "pick a version below"
                  // banner used to show unconditionally, even here where
                  // there is nothing below to pick. Split into two states
                  // instead: this one still reminds about pushing (in
                  // case the user just resolved the last one), without
                  // the now-nonsensical "pick a version" line.
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('No unresolved conflicts.',
                              style: TextStyle(color: kTextMid, fontSize: 15)),
                          const SizedBox(height: 8),
                          Text(
                            'If you just resolved one, tap PUSH on the '
                            'home screen to sync your desktop.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: kTextDim, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                // Entries are already sorted most-recent-first (see
                // _scan above), so "recent" is always a leading prefix -
                // splitIndex is where it ends. Only entries less than an
                // hour old count as "recent"; an all-recent or all-older
                // list gets no divider at all, since there's nothing to
                // visually separate.
                final now = DateTime.now();
                bool isRecent(ConflictEntry e) {
                  final t = _parseWhen(e.when);
                  return t != null && now.difference(t) < const Duration(hours: 1);
                }
                final splitIndex = entries.indexWhere((e) => !isRecent(e));
                final hasSplit = splitIndex > 0 && splitIndex < entries.length;
                // 2026-08-26: real feedback, live - "just need the
                // Conflicts page finished." Reference cleanup entries
                // (leftover "kept for reference" callouts, real conflicts
                // are handled above) are appended into this SAME list -
                // refHeaderIndex is where their section header sits, one
                // flat scrollable instead of nesting a second scrollable
                // inside this one.
                final hasRefs = refs.isNotEmpty;
                final refHeaderIndex = entries.length;
                // 2026-08-26: real feedback, live, from the validated
                // mockup at claude.ai/code/artifact/27d803c3 - a closing
                // line on Delete's scope, same idea as the "resolving
                // here only updates this phone" banner above but scoped
                // to this section specifically. One more trailing slot
                // in the same flat list, only when there's actually a
                // reference section to close out.
                final hintIndex = refHeaderIndex + refs.length + 1;
                final totalCount =
                    entries.length + (hasRefs ? 2 + refs.length : 0);
                return Column(
                  children: [
                    // 2026-08-26: real feedback, live - "these steps are
                    // needed in the moment, not some obscure guide."
                    // Moved here (only shown when there is actually
                    // something to pick below) after the same banner as a
                    // fixed top-of-page fixture read as nonsensical in the
                    // empty state - "Conflicts screen makes no sense now"
                    // - see the empty-state branch above for that half.
                    // Only shown when there's a real conflict to resolve -
                    // it doesn't apply to the reference-cleanup section.
                    if (entries.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        color: kSurface,
                        child: Text(
                          'Pick a version below to resolve, then tap PUSH '
                          'on the home screen to sync your desktop - '
                          'resolving here only updates this phone.',
                          style: TextStyle(color: kTextMid, fontSize: 13),
                        ),
                      ),
                    Expanded(
                      child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: totalCount,
                  separatorBuilder: (_, i) {
                    if (i >= entries.length - 1) return const SizedBox(height: 4);
                    return hasSplit && i == splitIndex - 1
                        ? const _EarlierDivider()
                        : Divider(color: kTextDim);
                  },
                  itemBuilder: (context, i) {
                    if (i == refHeaderIndex) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 8),
                        child: Text('Old versions (${refs.length})',
                            style: TextStyle(
                                color: kTextMid,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      );
                    }
                    if (hasRefs && i == hintIndex) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                            'Delete only affects this device until you sync.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: kTextDim, fontSize: 12)),
                      );
                    }
                    if (i > refHeaderIndex) {
                      final ref = refs[i - refHeaderIndex - 1];
                      return ReferenceCalloutTile(
                          entry: ref,
                          onDelete: () => _deleteRef(ref),
                          // Undo needs an exact swap span (see
                          // ReferenceEntry's own doc) - null on an older
                          // note resolved before that marker existed,
                          // which the tile reads as "not offered" rather
                          // than a broken button.
                          onUndo: ref.keptMarkerStart == null
                              ? null
                              : () => _undoRef(ref));
                    }
                    final e = entries[i];
                    // 2026-08-20: this exact conflict was resolved before
                    // and has now reappeared - most likely Obsidian's own
                    // cache reverting the write (see resolved_watchlist.dart)
                    // rather than a brand new conflict. Called out
                    // explicitly instead of looking like an unremarkable
                    // first-time entry, since the user already thought
                    // this one was handled.
                    final reappeared = _revertedPaths.contains(e.filePath);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: reappeared
                          ? const Icon(Icons.warning_amber,
                              color: Colors.amber, size: 22)
                          : null,
                      title: Text(e.filePath,
                          style: TextStyle(color: kStar, fontSize: 15)),
                      subtitle: Text(
                        reappeared
                            ? 'Resolved earlier, but this looks like it '
                                'came back - possibly reverted by Obsidian. '
                                'Check the backup note if unsure.'
                            : (e.versions.length > 2
                                ? '${e.versions.length - 1} unresolved versions '
                                    'stacked - most recent by ${e.who}'
                                : (e.when != null
                                    ? 'Conflicting change by ${e.who} - ${e.when}'
                                    : 'Conflicting change by ${e.who}')),
                        // 2026-08-20: real feedback, live - "too dark
                        // and grey", same complaint this screen has hit
                        // repeatedly today on dim/small text (the
                        // divider, the dialog backup line) - kStar/14px
                        // matches how those were fixed.
                        style: TextStyle(
                            color: reappeared ? Colors.amber : kStar,
                            fontSize: 14),
                      ),
                      trailing:
                          Icon(Icons.chevron_right, color: kTextDim),
                      onTap: () async {
                        final result =
                            await Navigator.push<ConflictResolvedResult>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ConflictPickerScreen(
                                repo: widget.repo, entry: e),
                          ),
                        );
                        if (result?.resolved == true) {
                          setState(() => _future = _scan());
                          // 2026-08-19: tried deep-linking straight to
                          // the exact backup note (obsidian://open?
                          // vault=...&file=...) - real device testing
                          // found Obsidian doesn't honor the folder
                          // portion of that path the way expected: it
                          // silently opened a same-named file from a
                          // completely unrelated old vault-backup
                          // snapshot instead, twice, with two different
                          // URL-encoding approaches. Showing WRONG
                          // content is worse than making the user
                          // navigate themselves, so this fell back to
                          // opening just the vault (already
                          // proven-reliable elsewhere - see
                          // linking_controller.dart's openObsidianNow())
                          // paired with an explicit folder name in the
                          // message, rather than a broken file-specific
                          // link.
                          final vaultName = result?.vaultName;
                          if (vaultName != null && context.mounted) {
                            // 2026-08-19: real bug, live - "Both
                            // versions" is wrong once a note has 3+
                            // stacked versions (see the Kanban
                            // multi-version test this session), not
                            // just the common 2-way case.
                            final versionWord = e.versions.length == 2
                                ? 'Both versions'
                                : 'All ${e.versions.length} versions';
                            // 2026-08-19: "why is the button link needed?
                            // ... make 'backed up' a link" - first pass
                            // linked the verb. Real follow-up: "ideally
                            // the link would be better in the actual
                            // location the text says at the end of the
                            // sentence" - a link should name the
                            // destination, not the action, so it moved
                            // onto "LocalSync Conflict Backups" instead.
                            //
                            // 2026-08-20: a same-session A/B test
                            // confirmed which note Obsidian shows after
                            // this tap tracks whatever was on-screen in
                            // Obsidian right before switching away, not
                            // this button - it never controlled the
                            // destination either way, by either wording.
                            // Reverted an "open Obsidian" rewording that
                            // tried to hedge around that, per direct
                            // instruction to keep the original text.
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: kSurface,
                                content: Text.rich(
                                  TextSpan(
                                    style: TextStyle(
                                        color: kStar, fontSize: 15),
                                    children: [
                                      TextSpan(
                                          text: 'Resolved. $versionWord '
                                              'backed up in '),
                                      TextSpan(
                                        text: 'LocalSync/Conflict Backups',
                                        style: TextStyle(
                                          color: kGreen,
                                          fontWeight: FontWeight.bold,
                                          decoration:
                                              TextDecoration.underline,
                                        ),
                                        recognizer: TapGestureRecognizer()
                                          ..onTap = () {
                                            IosAppServiceImpl().openObsidian(
                                                vaultName: vaultName);
                                          },
                                      ),
                                      // 2026-08-26: real feedback, live -
                                      // "these user actions like reboot
                                      // tab or vault needs to be noted in
                                      // the phone Conflicts screen in the
                                      // moment of the relevant fix." Real
                                      // testing hit Obsidian (desktop AND
                                      // phone) still showing old note
                                      // content after a background file
                                      // change - the file itself was
                                      // confirmed correct on disk both
                                      // times, Obsidian's own editor just
                                      // hadn't noticed. Told here, right
                                      // where a resolution just wrote to
                                      // this exact note.
                                      const TextSpan(
                                          text: '. If it still looks '
                                              'unchanged in Obsidian, '
                                              'close and reopen the note.'),
                                    ],
                                  ),
                                ),
                                duration: const Duration(seconds: 10),
                              ),
                            );
                          }
                        }
                      },
                    );
                  },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// 2026-08-26: real feedback, live - "stop the eye bleed, simple buttons
// for this or that." The wording fix on _mergeCallout's leftover blocks
// (conflict_scanner.dart) answered "what is this" but still left "now
// what" as manually editing the note by hand in Obsidian - exactly the
// interface this screen already exists to avoid for real conflicts. This
// is that same idea applied to leftover reference content: one real
// Delete button, backed up first (deleteReferenceCallout), no note-
// editing required. Public (not `_ReferenceCalloutTile`) so it can be
// preview-tested in isolation, same pattern as DiagCard.
// 2026-08-26: real feedback, live, many rounds - final shape settled via
// an HTML mockup (real device screenshots weren't practical mid-session):
// left/right compare (same principle as the real conflict picker's
// vimdiff-style view, "comparing data is easier left and right, not
// above and below"), green = what's actually in the note now, amber =
// the leftover that isn't - named by WHERE it is ("IN CONFLICT
// BACKUPS", not a bare "NOT IN NOTE" with a separate reassurance line -
// "why not replace NOT IN NOTE with IN CONFLICT BACKUPS?"). The amber
// side is a real ExpansionTile, not a link - "I prefer dropdown for
// immediate results and performance" - reading the actual leftover text
// never leaves this screen.
class ReferenceCalloutTile extends StatefulWidget {
  final ReferenceEntry entry;
  final VoidCallback onDelete;
  // 2026-08-27: null when entry.keptMarkerStart is null (an older note,
  // resolved before Undo had an exact span to swap - see
  // ReferenceEntry's own doc) - the UNDO button is left off entirely
  // for that case rather than shown disabled with no explanation.
  final VoidCallback? onUndo;
  const ReferenceCalloutTile({
    super.key,
    required this.entry,
    required this.onDelete,
    this.onUndo,
  });

  @override
  State<ReferenceCalloutTile> createState() => _ReferenceCalloutTileState();
}

class _ReferenceCalloutTileState extends State<ReferenceCalloutTile> {
  // 2026-08-27: real feedback, live - "arrows point right, need to point
  // down when text is selected to show and point right when not showing
  // text." Both ExpansionTiles below were StatelessWidget-static (see
  // their own 2026-08-26 comments) because the built-in rotating chevron
  // only comes for free through controlAffinity/trailing, and that
  // placement was already ruled out for the amber/green wrap case just
  // above. Tracking expand state here instead, one bool per tile, and
  // rotating the same static icon manually.
  bool _keptExpanded = false;
  bool _droppedExpanded = false;

  ReferenceEntry get entry => widget.entry;
  VoidCallback get onDelete => widget.onDelete;
  VoidCallback? get onUndo => widget.onUndo;

  // Only the dropped side's origin is actually tracked (entry.label,
  // written by conflict_scanner.dart's _mergeCallout as "who - when").
  String get _droppedWho => entry.label.split(' - ').first.trim();

  // 'yours' is the literal string conflict_scanner.dart's ConflictVersion
  // uses for "this exact device" (see its own doc) - never a display
  // name, so it's checked verbatim rather than guessed at.
  bool get _droppedIsYours => _droppedWho.toLowerCase() == 'yours';

  // 2026-08-26: real feedback, live, using the finished mockup at
  // claude.ai/code/artifact/27d803c3 as the reference - both sides need
  // a device identity, not just the dropped one. "This device" instead
  // of a bare "yours" (never shown to the user verbatim elsewhere either)
  // for the common case of your own edit getting dropped.
  // 2026-08-26: real feedback, live - "desktop obsidian to be Desktop
  // obsidian" - this is free-text the user typed into the device-name
  // setting (database_service.dart), shown verbatim before - sentence
  // case to match this app's own label convention rather than whatever
  // case it happened to be typed in.
  String get _droppedDisplayName => _droppedIsYours
      ? 'This device'
      : _droppedWho.isEmpty
          ? _droppedWho
          : _droppedWho[0].toUpperCase() + _droppedWho.substring(1);

  // The kept side's exact identity was never persisted - applyResolution
  // (conflict_scanner.dart) only keeps the winning text, not which
  // ConflictVersion.who it came from. But this app is always exactly two
  // devices, phone and one paired desktop (see database_service.dart's
  // device-name setting), so it's still fully determined by elimination:
  // dropped-is-yours means the kept side must be the desktop; anything
  // else dropped means the kept side must be yours. The desktop's exact
  // configured name isn't recoverable here though, so that branch uses a
  // generic label instead of guessing a name that might be wrong.
  bool get _keptIsThisDevice => !_droppedIsYours;
  String get _keptDisplayName =>
      _keptIsThisDevice ? 'This device' : 'Your other device';
  IconData get _droppedIcon => _droppedIsYours ? Icons.smartphone : Icons.computer;
  IconData get _keptIcon => _keptIsThisDevice ? Icons.smartphone : Icons.computer;

  // 2026-08-26: real feedback, live - "title has no name of what the
  // conflict [is] like" and "I need some sign that the conflict has
  // already been resolved." entry.label already carries who/when for
  // the dropped side but it was only ever surfaced inside the Delete
  // button's wording - nothing under the bare file-path title said who
  // or when, or that this was already handled. Reuses the top-level
  // _parseWhen this file already has for the main conflict list's own
  // YYYYMMDDhhmm dates.
  // 2026-08-26: real feedback, live - "change date to YYYYMMDDhhmm" -
  // the raw digits straight out of entry.label, not reformatted. Matches
  // this app's own timestamp shape everywhere else (backupTimestamp() in
  // vault_backup.dart, the main conflict list's raw `e.when`) instead of
  // a human-formatted date this one spot was the odd one out on.
  String? get _droppedWhenRaw {
    final parts = entry.label.split(' - ');
    return parts.length > 1 ? parts.last.trim() : null;
  }

  // 2026-08-26: real feedback, live - "verbose, but needed" - kept the
  // who/when/not-kept facts, dropped the "Already resolved" framing
  // (redundant: being in this "Old versions" section already says
  // that) to fit on one line instead of wrapping to two.
  String get _subtitle {
    final who =
        _droppedWho.isEmpty ? 'An earlier edit' : "$_droppedDisplayName's edit";
    final when = _droppedWhenRaw;
    return when == null ? '$who not kept' : '$who not kept - $when';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kSurface,
        border: Border(left: BorderSide(color: kTextDim, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(entry.filePath,
              style: TextStyle(
                  color: kStar, fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(_subtitle, style: TextStyle(color: kTextMid, fontSize: 12.5)),
          const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                    decoration: BoxDecoration(
                      color: kGreen.withValues(alpha: 0.08),
                      border: Border.all(color: kGreen.withValues(alpha: 0.35)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      // 2026-08-26: real feedback, live - "phone image and
                      // text to vertically align with desktop icon and
                      // text." Was MainAxisAlignment.center on both sides
                      // independently - fine when both boxes hold the same
                      // amount of content, but the amber side gained a
                      // Delete button (see below) making it taller, so
                      // centering each block within its own now-different
                      // total height pushed the icon/devname rows out of
                      // alignment with each other. Anchoring both to the
                      // top instead means they start at the same Y
                      // regardless of what either side has below them.
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Icon(_keptIcon, color: kGreen, size: 22),
                        const SizedBox(height: 4),
                        Text(_keptDisplayName,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: kTextMid, fontSize: 11)),
                        const SizedBox(height: 2),
                        // 2026-08-26: real feedback, live - "have a
                        // dropdown text for the phone side" too, mirroring
                        // the amber side's expandable preview. Uses
                        // entry.keptPreview (conflict_scanner.dart) - the
                        // kept side's text has no marker of its own, so
                        // it's recovered positionally rather than tagged,
                        // unlike the dropped side's entry.body.
                        Theme(
                          data: Theme.of(context)
                              .copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            dense: true,
                            tilePadding: EdgeInsets.zero,
                            childrenPadding:
                                const EdgeInsets.fromLTRB(4, 0, 4, 10),
                            iconColor: kGreen,
                            collapsedIconColor: kGreen,
                            // 2026-08-26: real feedback, live - same fix
                            // as the amber side's matching comment just
                            // below: built into title now (top-aligned,
                            // static), not controlAffinity, so this stays
                            // consistent with the amber side even though
                            // "IN NOTE NOW" itself is short enough not to
                            // wrap today.
                            trailing: const SizedBox.shrink(),
                            onExpansionChanged: (v) =>
                                setState(() => _keptExpanded = v),
                            title: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: AnimatedRotation(
                                    turns: _keptExpanded ? 0.25 : 0,
                                    duration:
                                        const Duration(milliseconds: 200),
                                    child: Icon(Icons.chevron_right,
                                        size: 16, color: kGreen),
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Expanded(
                                  child: Text('IN NOTE NOW',
                                      style: TextStyle(
                                          color: kGreen,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.4)),
                                ),
                              ],
                            ),
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                    entry.keptPreview.isEmpty
                                        ? '(nothing else above this in the note)'
                                        : entry.keptPreview,
                                    style: TextStyle(
                                        color: kStar, fontSize: 12, height: 1.4)),
                              ),
                            ],
                          ),
                        ),
                        // 2026-08-27: real feedback, live - "build the
                        // undo." Mirrors the amber side's DELETE NOTE
                        // button below - same width/placement pattern,
                        // green-accented to match this side. Left off
                        // entirely (not shown disabled) when onUndo is
                        // null - see ReferenceCalloutTile's own doc.
                        if (onUndo != null) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: onUndo,
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: kGreen),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                              ),
                              child: Text('UNDO',
                                  style: TextStyle(
                                      color: kGreen,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // 2026-08-26: real feedback, live - "left and right
                // squares to have a space between them" - was 8, bumped
                // to 12.
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.08),
                      border:
                          Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Icon(_droppedIcon, color: Colors.amber, size: 22),
                        const SizedBox(height: 4),
                        Text(_droppedDisplayName,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: kTextMid, fontSize: 11)),
                        const SizedBox(height: 2),
                        // 2026-08-26: real feedback, live - checked
                        // against resolveConflict (conflict_scanner.dart):
                        // this content is already written to LocalSync/
                        // Conflict Backups the moment the conflict was
                        // resolved, before this callout was even folded
                        // into the note. "IN CONFLICT BACKUPS" is a fact
                        // about what already happened, not a promise
                        // about what Delete below will do - matches the
                        // finished mockup at
                        // claude.ai/code/artifact/27d803c3.
                        Theme(
                          data: Theme.of(context)
                              .copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            dense: true,
                            tilePadding: EdgeInsets.zero,
                            childrenPadding:
                                const EdgeInsets.fromLTRB(4, 0, 4, 10),
                            iconColor: Colors.amber,
                            collapsedIconColor: Colors.amber,
                            // 2026-08-26: real feedback, live - "left
                            // arrow to be left of IN" - controlAffinity's
                            // built-in leading icon vertically centers
                            // against the WHOLE title block, so once "IN
                            // CONFLICT BACKUPS" wraps to two lines the
                            // arrow floats between them, not next to "IN"
                            // specifically. ExpansionTile has no
                            // titleAlignment passthrough (checked against
                            // the installed 3.44.9 SDK source directly),
                            // so the icon is built into title itself here,
                            // top-aligned via the Row's own
                            // crossAxisAlignment - trailing suppressed so
                            // the built-in icon doesn't also show. 2026-08-27:
                            // rotated manually via _droppedExpanded now the
                            // tile tracks its own state - see the State
                            // class just above this widget's declaration.
                            trailing: const SizedBox.shrink(),
                            onExpansionChanged: (v) =>
                                setState(() => _droppedExpanded = v),
                            title: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: AnimatedRotation(
                                    turns: _droppedExpanded ? 0.25 : 0,
                                    duration:
                                        const Duration(milliseconds: 200),
                                    child: const Icon(Icons.chevron_right,
                                        size: 16, color: Colors.amber),
                                  ),
                                ),
                                const SizedBox(width: 2),
                                const Expanded(
                                  child: Text('IN CONFLICT BACKUPS',
                                      style: TextStyle(
                                          color: Colors.amber,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.4)),
                                ),
                              ],
                            ),
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(entry.body,
                                    style: TextStyle(
                                        color: kStar, fontSize: 12, height: 1.4)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        // 2026-08-26: real feedback, live - "make button
                        // same width and vertically aligned with right
                        // section." A separate Row below, sized to match
                        // via identical flex proportions, wasn't reliably
                        // exact - nested directly inside this same amber
                        // Expanded instead, so the width match is exact
                        // by construction, not by two Rows happening to
                        // agree. "Change DELETE image, to DELETE NOTE" -
                        // device icon replaced with a second word, per
                        // direct instruction. Worth a second look though:
                        // this only ever removes the folded callout block
                        // from the note (see deleteReferenceCallout,
                        // conflict_repair.dart), never the note itself -
                        // "DELETE NOTE" reads as more destructive than
                        // what actually happens.
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: onDelete,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.redAccent),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            child: const Text('DELETE NOTE',
                                style: TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// 2026-08-20: separates a fresh conflict from older, already-known
// clutter below it - built-in icon, not a custom SVG. This app already
// decided against hand-drawn SVG art for exactly this kind of small
// inline glyph (see key_pairing_trigger.dart's asset history) - real
// rendering risk (invisible gaps, wrong fills) with no way to preview
// before a full rebuild+sideload cycle, for something a stock icon
// already says clearly enough.
class _EarlierDivider extends StatelessWidget {
  const _EarlierDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          // 2026-08-20: real feedback, live - "too dark and small",
          // same complaint this app has hit before on other dim/small
          // labels (see conflicts_screen.dart's own _SafetyStep,
          // conflict_picker_screen.dart's dialog text) - kTextMid/14px
          // matches how those were fixed.
          Icon(Icons.history, color: kTextMid, size: 18),
          const SizedBox(width: 8),
          Text('Earlier - from before',
              style: TextStyle(color: kTextMid, fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(child: Divider(color: kTextDim)),
        ],
      ),
    );
  }
}

class _SafetyStep extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SafetyStep({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: kGreen, size: 26),
        const SizedBox(height: 4),
        // 2026-08-18: bumped from the old paragraph's dim 13px/kTextMid
        // to kStar/14px - "too small and dark, make easier to read".
        Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(color: kStar, fontSize: 12)),
      ],
    );
  }
}
