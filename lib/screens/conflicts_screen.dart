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
                IconButton(
                  icon: Icon(Icons.info_outline, color: kTextMid),
                  tooltip: 'How this works',
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      backgroundColor: kSurface,
                      title: Text('How conflicts are kept safe',
                          style: TextStyle(color: kStar, fontSize: 17)),
                      // 2026-08-18: "still too small and dark", "need a
                      // clearer location" - bumped to kStar/16px to
                      // match the rest of the app's readable text, and
                      // named the exact spot instead of the vague "in
                      // your vault": a normal top-level folder, visible
                      // in Obsidian's own file list like any other
                      // folder, not hidden or app-only.
                      content: Text(
                        'Resolving a conflict always saves both full '
                        'versions first, before anything is changed.\n\n'
                        'Location: open Obsidian, look at your file '
                        'list (the folder icon in the left sidebar) - '
                        'there\'s a folder called "LocalSync Conflict '
                        'Backups" at the top level, right alongside '
                        'your other folders. Nothing is lost, even if '
                        'you pick the wrong one - just open the note '
                        'inside it to find the other version.\n\n'
                        // 2026-08-26: real feedback, live - "I need this
                        // advice when using the app... here are the
                        // steps to sync after the conflict." Resolving
                        // here only changes this device - a real test
                        // session needed to ask directly what to do
                        // next, so it's spelled out here now instead of
                        // only ever living in a chat answer.
                        'After resolving everything below: tap PUSH (or '
                        'run Sync) on the home screen. Resolving a '
                        'conflict here only updates this device - your '
                        'desktop won\'t see the result until you push.',
                        style: TextStyle(color: kStar, fontSize: 16),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text('Got it',
                              style: TextStyle(color: kStar, fontSize: 15)),
                        ),
                      ],
                    ),
                  ),
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
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: kGreen),
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
                final totalCount =
                    entries.length + (hasRefs ? 1 + refs.length : 0);
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
                    if (i > refHeaderIndex) {
                      final ref = refs[i - refHeaderIndex - 1];
                      return ReferenceCalloutTile(
                          entry: ref, onDelete: () => _deleteRef(ref));
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
                                        text: 'LocalSync Conflict Backups',
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
class ReferenceCalloutTile extends StatelessWidget {
  final ReferenceEntry entry;
  final VoidCallback onDelete;
  const ReferenceCalloutTile({
    super.key,
    required this.entry,
    required this.onDelete,
  });

  // Only the dropped side's origin is actually tracked (entry.label,
  // written by conflict_scanner.dart's _mergeCallout as "who - when") -
  // the kept side has no equivalent data, so it's labeled generically
  // ("this note") rather than guessing a device it might not be.
  String get _droppedWho => entry.label.split(' - ').first.trim();

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
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle, color: kGreen, size: 20),
                        const SizedBox(height: 4),
                        Text('IN NOTE NOW',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: kGreen,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.08),
                      border:
                          Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Theme(
                      data: Theme.of(context)
                          .copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        dense: true,
                        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                        childrenPadding:
                            const EdgeInsets.fromLTRB(10, 0, 10, 10),
                        iconColor: Colors.amber,
                        collapsedIconColor: Colors.amber,
                        title: const Text('IN CONFLICT BACKUPS',
                            style: TextStyle(
                                color: Colors.amber,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4)),
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
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline,
                  size: 16, color: Colors.redAccent),
              label: Text(
                  'DELETE ${_droppedWho.isEmpty ? "THIS EDIT" : "$_droppedWho'S EDIT"}'
                      .toUpperCase(),
                  style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.redAccent),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
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
