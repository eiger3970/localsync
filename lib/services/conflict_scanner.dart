// services/conflict_scanner.dart
//
// 2026-08-18: step 1 of the conflict-picker plan (see sync_service.dart's
// SyncNeedsConfirmation header comment for the sibling deletion-safety
// feature this followed) - "sometimes users need to know more than a
// number" led to that dialog's drill-down; this is the same instinct
// applied to conflicts. No new persisted state: conflicts already live
// as plain text in the vault (written by sync_service.dart's
// _repairConflictMarkers), so a live scan is always accurate and
// self-clearing once a file's resolved - nothing to keep in sync
// separately.
//
// Extended same day for step 2 (the tap-to-pick diff view): both sides
// of a markdown conflict are now cleanly delimited in the file
// (_repairConflictMarkers wraps "yours" in its own callout, not just
// "theirs" as before) so the actual ours/theirs text - not just the
// who/when metadata - can be pulled back out and diffed. Kanban
// conflicts were already cleanly bounded (a card is one line, "ours" is
// just the line before the %% CONFLICT-OTHER %% run) - no format change
// needed there.
//
// [matchStart]/[matchEnd] are byte offsets into the file's raw content -
// the eventual "apply my pick" step replaces exactly that span with
// whichever side won, nothing fuzzier than a direct substring replace.

import 'dart:convert';
import 'dart:io';
import 'conflict_repair.dart' show journalOrderedEntries, repositionedReplace;
import 'database_service.dart';
import 'localsync_folder.dart';
import 'vault_backup.dart';
import 'vault_folder_service.dart';

/// One side of a conflict. [who]/[when] are null for index 0 ("yours" -
/// this device's own version; the picker screen shows the real device
/// name for that slot instead of the literal label text).
class ConflictVersion {
  final String who;
  final String? when;
  final String body;
  const ConflictVersion({required this.who, this.when, required this.body});
}

class ConflictEntry {
  final String filePath; // relative to the vault root
  // 2026-08-19: was a fixed ours/theirs pair - couldn't represent more
  // than one other side. See sync_service.dart's _extractStackedVersions
  // for why a note can now genuinely carry 3+ stacked, still-unresolved
  // versions (repeated conflicts on the same line/card before the user
  // ever resolved the previous one) - index 0 is always "yours", the
  // rest are every other still-unresolved version, oldest first.
  final List<ConflictVersion> versions;
  final bool isKanban;
  final int matchStart;
  final int matchEnd;
  const ConflictEntry({
    required this.filePath,
    required this.versions,
    required this.isKanban,
    required this.matchStart,
    required this.matchEnd,
  });

  String get ours => versions.first.body;
  // Kept for call sites that only ever dealt with exactly one other
  // side (the common case) - "theirs" is the single most-recent other
  // version. Callers that need every stacked version should read
  // [versions] directly.
  String get theirs => versions.length > 1 ? versions.last.body : '';
  String get who => versions.length > 1 ? versions.last.who : '';
  String? get when => versions.length > 1 ? versions.last.when : null;
}

// 2026-08-19: matches one whole run of consecutive, non-nested SYNC
// CONFLICT callouts - one-or-more, not exactly two - since
// _repairConflictMarkers now flattens any number of previously-stacked
// versions into siblings at this same depth instead of nesting them.
// [-—] accepts a regular dash or an em dash - see conflict_repair.dart's
// calloutHeaderPattern comment: content written before the em-dash fix
// must stay parseable, not silently invisible to this scanner.
// Deliberately `\n?` (exactly one optional blank line), not wider -
// see conflict_repair.dart's _stackedRunPattern comment for why: a
// wider tolerance was tried and reverted because there is no reliable
// way to tell "these are siblings of one conflict, separated by an
// accumulated extra blank line" apart from "these are two unrelated
// conflicts that just happen to sit near each other" - both shapes
// were observed in the same real file. `\n?` matches what this app's
// own write template always produces between true siblings, so a
// conflict separated from a true sibling by 2+ blank lines (legacy
// content only, so far) stays split into its own entry rather than
// risk merging unrelated content together.
// 2026-09-07: [+-] accepts both the older always-expanded (+) and
// current collapsed-by-default (-) fold state - see conflict_repair.
// dart's calloutHeaderPattern comment for why the write side changed.
// [^\n]* after the closing paren tolerates the "- open LocalSync..."
// suffix new content carries (or its absence, on older content).
final _stackedBlockPattern = RegExp(
  r'(?:> \[!(?:info|warning)\][+-] SYNC CONFLICT [-—] .+? \(review and delete one\)[^\n]*\n'
  r'(?:> (?!\[!(?:info|warning)\][+-] SYNC CONFLICT).*\n?)*\n?)+',
);
// 2026-08-19: body capture stops before another header line instead of
// greedily swallowing it - see conflict_repair.dart's
// consolidateStackedRuns for the real device bug this caused (an old
// header with no body of its own read as a version whose "body" was
// literally the next header's raw text). The write side is now
// guaranteed to always produce a single already-consolidated run with
// no header directly following another header, but this stays
// defensive rather than relying on that invariant silently.
final _calloutPattern = RegExp(
  r'> \[!(?:info|warning)\][+-] SYNC CONFLICT [-—] (.+?) \(review and delete one\)[^\n]*\n'
  r'((?:> (?!\[!(?:info|warning)\][+-] SYNC CONFLICT).*\n?)*)',
);

final _kanbanPairedPattern = RegExp(
  r'^(.+)\n((?:%% CONFLICT-OTHER \(.+?\): .*%%\n?)+)',
  multiLine: true,
);
final _kanbanLinePattern = RegExp(r'%% CONFLICT-OTHER \((.+?)\): (.*) %%');
final _kanbanFrontmatterPattern = RegExp(r'^kanban-plugin:', multiLine: true);

String _stripQuoteBlock(String block) => block
    .split('\n')
    .where((l) => l.isNotEmpty)
    .map((l) => l.startsWith('> ') ? l.substring(2) : l.replaceFirst('>', ''))
    .join('\n');

/// Scans every `.md` file under [vaultPath] for unresolved conflict
/// markers. A file with several conflicting sections yields several
/// entries, one per marker - not collapsed to one row per file.
Future<List<ConflictEntry>> scanForConflicts(String vaultPath) async {
  final entries = <ConflictEntry>[];
  final dir = Directory(vaultPath);
  if (!await dir.exists()) return entries;
  final skipFolders = localSyncFolders(vaultPath);

  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.md')) continue;
    // 2026-08-18: real device finding - a vault linked to a
    // non-already-empty folder gets a "Vault Backup <timestamp>"
    // snapshot (see vault_backup.dart) that can contain old,
    // already-stale conflict markers from before. Scanning inside
    // backup folders surfaced those as live, actionable conflicts -
    // confusing and wrong, since resolving a snapshot of the past
    // isn't a real action. Same reasoning excludes this scanner's own
    // "Conflict Backups" output from being re-scanned as a conflict,
    // though that one's format doesn't match the callout patterns
    // below anyway. Both now share one kLocalSyncFolderName parent
    // (2026-08-26), so one prefix check covers both; the two legacy
    // top-level names are still excluded too, for vaults that had
    // conflicts resolved before that move and still have the old
    // top-level folders sitting around unmigrated.
    final relPath = entity.path.replaceFirst('${dir.path}/', '');
    if (isInLocalSyncFolder(relPath, skipFolders) ||
        relPath.startsWith('LocalSync Vault Backup ') ||
        relPath.startsWith('LocalSync Conflict Backups/')) {
      continue;
    }
    final String content;
    try {
      content = await entity.readAsString();
    } catch (_) {
      continue; // unreadable file - skip, same as the repair pass does
    }
    if (!content.contains('SYNC CONFLICT') &&
        !content.contains('CONFLICT-OTHER')) {
      continue;
    }
    final isKanban = _kanbanFrontmatterPattern.hasMatch(content);

    if (isKanban) {
      for (final m in _kanbanPairedPattern.allMatches(content)) {
        final oursLine = m.group(1)!;
        final commentLines = _kanbanLinePattern.allMatches(m.group(2)!);
        if (commentLines.isEmpty) continue;
        // Kanban conflicts can't nest (a card is always one line), so
        // no flattening is needed here - but several devices can still
        // stack several CONFLICT-OTHER comments on the same card before
        // anyone resolves it. Each becomes its own version, same as the
        // non-Kanban path below, instead of collapsing them into one.
        entries.add(ConflictEntry(
          filePath: relPath,
          versions: [
            ConflictVersion(who: 'yours', body: oursLine),
            for (final c in commentLines)
              ConflictVersion(who: c.group(1)!, body: c.group(2)!),
          ],
          isKanban: true,
          matchStart: m.start,
          matchEnd: m.end,
        ));
      }
    } else {
      for (final block in _stackedBlockPattern.allMatches(content)) {
        final versions = <ConflictVersion>[];
        for (final m in _calloutPattern.allMatches(block.group(0)!)) {
          final rawLabel = m.group(1)!;
          // Accepts either separator - see calloutHeaderPattern's
          // comment in conflict_repair.dart: an older, already-written
          // label can still carry the em dash this app used to write.
          var sep = rawLabel.indexOf(' - ');
          if (sep == -1) sep = rawLabel.indexOf(' — ');
          versions.add(ConflictVersion(
            who: sep == -1 ? rawLabel : rawLabel.substring(0, sep),
            when: sep == -1 ? null : rawLabel.substring(sep + 3),
            body: _stripQuoteBlock(m.group(2)!),
          ));
        }
        if (versions.length < 2) continue; // malformed - nothing to act on
        entries.add(ConflictEntry(
          filePath: relPath,
          versions: versions,
          isKanban: false,
          matchStart: block.start,
          matchEnd: block.end,
        ));
      }
    }
  }
  return entries;
}

/// 2026-08-18: "fear of tapping an irreversible action and losing
/// critical data forever" - a real gap, not just a wording problem. The
/// picker screen already asks for a second explicit confirm before
/// calling this, but the confirm alone doesn't make anything
/// recoverable - this does. Every stacked version gets written to a
/// plain Obsidian note before the file is touched, so whichever ones
/// get discarded are still sitting in the vault afterward, in plain
/// text, no git knowledge required to find them.
///
/// 2026-08-19: returns the backup file's path relative to the vault
/// root (e.g. "LocalSync/Conflict Backups/note - 202608191945.md") -
/// real user feedback, live: "where is 'LocalSync Conflict Backups'?
/// give me an absolute path... humans don't need to know petty shite,
/// that's for computer machines to deal with." The app already knows
/// exactly where it just wrote this file - the caller uses this to
/// deep-link straight to it in Obsidian (obsidian://open?vault=...
/// &file=...) instead of describing a folder to go find by hand.
Future<String> _backupConflictBeforeResolving(
  String vaultPath,
  ConflictEntry entry,
) async {
  final backupDir =
      Directory(conflictBackupsDir(vaultPath));
  await backupDir.create(recursive: true);
  final baseName = entry.filePath.split('/').last.replaceAll('.md', '');
  final backupFileName = '$baseName - ${backupTimestamp()}.md';
  final backupFile = File('${backupDir.path}/$backupFileName');
  final sections = entry.versions.asMap().entries.map((e) {
    final v = e.value;
    final heading = e.key == 0
        ? 'Your version'
        : (v.when != null ? '${v.who} - ${v.when}' : v.who);
    return '## $heading\n\n${v.body}\n';
  }).join('\n');
  await backupFile.writeAsString(
    '# Conflict backup\n\n'
    'Original file: ${entry.filePath}\n\n'
    '$sections',
  );
  return '${conflictBackupsRelPath(vaultPath)}/$backupFileName';
}

/// Pure string transform - given the file's current [content] and the
/// [entry]/[chosen] the user picked, returns the updated content. Split
/// out from [resolveConflict] so this is unit-testable without file I/O,
/// same pattern as conflict_repair.dart.
///
/// 2026-08-20: real device bug - a Kanban resolution used to always
/// replace the matched span with a bare [chosen] (no trailing newline),
/// on the assumption a Kanban conflict's replacement never needs one.
/// Wrong: `_kanbanPairedPattern`'s trailing `%%\n?` is optional and
/// matches a real newline when the conflict isn't the last thing in the
/// file - so the matched span often *did* consume the newline
/// separating the card from whatever came after it (e.g. a `## Done`
/// heading), and dropping it merged the two onto one line, breaking the
/// board's structure. Now preserves whatever trailing newline the
/// original matched span actually had, for both Kanban and non-Kanban,
/// instead of a fixed per-type assumption.
/// Assumes [entry]'s offsets are still valid against [content] - callers
/// must check that themselves (see resolveConflict's own guard) since a
/// pure function has no good way to signal "nothing to do" separately
/// from "here is the unchanged content".
///
/// 2026-08-25: real feedback, live - "I don't want 1 version kept and
/// the other version... moved to LocalSync Conflict Backups. I need all
/// or part of that data onto this device, merged as in gitmerge...
/// similar to a git merge." Picking used to fully replace the span with
/// just [chosen] - the other version(s)' data left this file entirely,
/// recoverable only from a separate backup file. Now (non-Kanban only -
/// a Kanban card is one line, and this callout is several) every
/// version NOT chosen is appended right after [chosen] as a collapsed
/// callout, in the same file, using the same
/// "> [!kind] LABEL - detail\n> body" shape _repairConflictMarkers
/// already writes for SYNC CONFLICT - [!question]- instead of
/// [!warning]+ so it reads as "kept for reference," not "still
/// unresolved," and so this scanner's own SYNC-CONFLICT-only pattern
/// doesn't pick it back up as a fresh conflict. This is the free tier's
/// merge - full-text, not a fine-grained content union (that's the
/// paid put/yank tier) - but nothing is left only in a backup file
/// anymore; the user edits it down right here, same as resolving a real
/// git merge conflict block.
///
/// 2026-08-27: real feedback, live - "fear of reversing a mistaken git
/// merge" plus a direct ask to build Undo for a resolved conflict.
/// [_mergeCallout] already gives the dropped side an exact, regex-
/// matchable span (its own callout block) - the kept side never had
/// one, only a heuristic best-effort lookback (see [_extractKeptPreview]
/// and [ReferenceEntry.keptPreview]'s own doc for why that's a preview,
/// not a safe span to swap). A byte-precise Undo needs both sides
/// bounded exactly, so [chosen] is now wrapped the same way, in an HTML
/// comment pair instead of a callout - Obsidian renders `<!-- -->` as
/// fully invisible in reading view, so the kept text still reads as
/// plain, unfolded prose, unlike a collapsed callout which would hide
/// it. Only written when there's actually a reference callout to pair
/// it with (the same `notChosen.isEmpty`/Kanban gate below) - a plain
/// pick with nothing dropped has nothing for Undo to swap against.
String applyResolution(String content, ConflictEntry entry, String chosen,
    {bool keepLeftoverInNote = false}) {
  final matchedSpan = content.substring(entry.matchStart, entry.matchEnd);
  final trailingNewline = matchedSpan.endsWith('\n') ? '\n' : '';
  final notChosen = entry.versions.where((v) => v.body != chosen).toList();
  String merged;
  if (entry.isKanban || notChosen.isEmpty || !keepLeftoverInNote) {
    merged = chosen;
  } else {
    final chosenIndex = entry.versions.indexWhere((v) => v.body == chosen);
    final chosenLabel = chosenIndex <= 0
        ? 'Your version'
        : (entry.versions[chosenIndex].when != null
            ? '${entry.versions[chosenIndex].who} - ${entry.versions[chosenIndex].when}'
            : entry.versions[chosenIndex].who);
    final keptBlock = '<!-- LOCALSYNC-KEPT label="$chosenLabel" -->\n'
        '$chosen\n'
        '<!-- LOCALSYNC-KEPT-END -->\n\n';
    merged = '$keptBlock${notChosen.map(_mergeCallout).join('\n')}';
  }
  final replacement = '$merged$trailingNewline';
  // 2026-09-14: real feedback, live, two real cases - "the times are
  // wrong again... your future conflict resolutions correctly clean up
  // the clock text data right?" They didn't until now - see
  // repositionedReplace's own doc (conflict_repair.dart) for why. Falls
  // straight through to the old plain replaceRange whenever replacement
  // has no leading time of its own (including the keepLeftoverInNote
  // case just above, which wraps $merged in an HTML comment - never a
  // bare HHMM time, so nothing to reposition by, same as before).
  return repositionedReplace(
      content, entry.matchStart, entry.matchEnd, replacement);
}

/// One collapsed "kept for reference" callout for a version that wasn't
/// picked - see applyResolution's 2026-08-25 comment.
///
/// 2026-08-26: real feedback, live - "What do I do? Is this an Obsidian
/// error and unable to fix from the app?" The old wording ("Also in
/// desktop obsidian's version (edit in, or delete)") didn't say this was
/// already resolved - the content right above this callout in the note IS
/// the version that was kept; this is only the losing side, left in place
/// so nothing was silently dropped. [!question]- (not [!warning]+, and
/// deliberately not matching this scanner's own SYNC-CONFLICT-only
/// pattern) already meant "not active," but only to someone who already
/// knew that convention - spelled out directly now instead.
String _mergeCallout(ConflictVersion v) {
  final label = v.when != null ? '${v.who} - ${v.when}' : v.who;
  final quoted = v.body.split('\n').map((l) => '> $l').join('\n');
  return '> [!question]- Already resolved - kept for reference only, not '
      'an active conflict. This is $label\'s version that was NOT kept - '
      'copy anything you want from it, then delete this block whenever.\n'
      '$quoted';
}

// ─────────────────────────────────────────────
// "Kept for reference" cleanup - real, tap-to-delete
// ─────────────────────────────────────────────
//
// 2026-08-26: real feedback, live - "stop the eye bleed, simple buttons
// for this or that." The wording fix above answered "what is this," but
// left "now what" as manually editing the note by hand in Obsidian - the
// exact kind of interface this app's own Conflicts screen already exists
// to avoid for real conflicts. Same idea applied to _mergeCallout's
// leftover blocks: find them, offer one real Delete button, back up
// first (same safety convention as every other destructive action in
// this file).

final _referenceCalloutPattern = RegExp(
  r"> \[!question\]- Already resolved - kept for reference only, not an "
  r"active conflict\. This is (.+?)'s version that was NOT kept[^\n]*\n"
  r"((?:> .*\n?)*)",
);

class ReferenceEntry {
  final String filePath; // relative to the vault root
  final String label; // who/when this leftover version came from
  final String body; // the quoted content itself, for a short preview
  // 2026-08-26: real feedback, live - "have a dropdown text for the
  // phone side" too, mirroring [body] above for the dropped side. The
  // kept side's text was never itself tagged with any marker (see
  // applyResolution: only the dropped side gets wrapped in a callout),
  // so this is recovered positionally instead - see
  // scanForReferenceCallouts' extraction just below.
  final String keptPreview;
  final int matchStart;
  final int matchEnd;
  // 2026-08-27: exact span/label/content of the kept side's own
  // LOCALSYNC-KEPT marker (see applyResolution's doc) - null for a note
  // resolved before this marker existed. Undo is only offered
  // (conflicts_screen.dart's ReferenceCalloutTile) when these are
  // non-null - an older note has no exact, safe span to swap, so Undo
  // is simply unavailable for it rather than guessed at.
  final int? keptMarkerStart;
  final int? keptMarkerEnd;
  final String? keptLabel;
  final String? keptContent;
  const ReferenceEntry({
    required this.filePath,
    required this.label,
    required this.body,
    required this.keptPreview,
    required this.matchStart,
    required this.matchEnd,
    this.keptMarkerStart,
    this.keptMarkerEnd,
    this.keptLabel,
    this.keptContent,
  });
}

final _keptMarkerPattern = RegExp(
  r'<!-- LOCALSYNC-KEPT label="(.*?)" -->\n(.*?)\n<!-- LOCALSYNC-KEPT-END -->\n\n',
  dotAll: true,
);

String _truncateToPreview(String text) {
  final tail = text.length <= _maxLookback
      ? text
      : text.substring(text.length - _maxLookback);
  final lastParagraphBreak = tail.lastIndexOf('\n\n');
  final truncated = text.length > _maxLookback && lastParagraphBreak == -1;
  final shown =
      lastParagraphBreak == -1 ? tail : tail.substring(lastParagraphBreak + 2);
  return truncated ? '…${shown.trim()}' : shown.trim();
}

/// The kept side's text has no marker of its own (see ReferenceEntry.
/// keptPreview's doc) - it's just whatever content sits directly above
/// where this callout starts. Bounded to [_maxLookback] chars, then
/// trimmed to the last blank-line-separated paragraph within that
/// window if one exists - the most relevant tail, not an arbitrary mid-
/// sentence cut, and never the whole note even if this is the file's
/// only conflict and [chosen] itself was long.
const _maxLookback = 500;

String _extractKeptPreview(String content, int calloutStart) {
  final windowStart =
      calloutStart - _maxLookback > 0 ? calloutStart - _maxLookback : 0;
  var text = content.substring(windowStart, calloutStart).trimRight();
  final lastParagraphBreak = text.lastIndexOf('\n\n');
  final truncated = windowStart > 0 && lastParagraphBreak == -1;
  if (lastParagraphBreak != -1) text = text.substring(lastParagraphBreak + 2);
  text = text.trim();
  return truncated ? '…$text' : text;
}

/// Scans every `.md` file under [vaultPath] for "kept for reference"
/// callouts left behind by a merge resolution - see _mergeCallout above.
/// Skips backup folders for the same reason scanForConflicts does: their
/// whole purpose is to hold old content forever, not surface it as
/// something to act on.
Future<List<ReferenceEntry>> scanForReferenceCallouts(String vaultPath) async {
  final entries = <ReferenceEntry>[];
  final dir = Directory(vaultPath);
  if (!await dir.exists()) return entries;
  final skipFolders = localSyncFolders(vaultPath);

  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.md')) continue;
    if (entity.path.contains('/$kLocalSyncFolderName/')) continue;
    if (isInLocalSyncFolder(
        entity.path.substring(vaultPath.length + 1), skipFolders)) {
      continue;
    }
    if (entity.path.contains('/LocalSync Conflict Backups/')) continue;
    if (entity.path.contains('/LocalSync Vault Backup ')) continue;

    final content = await entity.readAsString();
    if (!content.contains('[!question]- Already resolved')) continue;
    final relPath = entity.path.substring(vaultPath.length + 1);

    for (final m in _referenceCalloutPattern.allMatches(content)) {
      // A LOCALSYNC-KEPT marker immediately precedes its paired
      // reference callout (applyResolution writes them together) - the
      // exact adjacency (km.end == m.start) is what makes this safe to
      // match up even with several conflicts/callouts in one file.
      int? keptStart, keptEnd;
      String? keptLabel, keptContent;
      for (final km in _keptMarkerPattern.allMatches(content)) {
        if (km.end == m.start) {
          keptStart = km.start;
          keptEnd = km.end;
          keptLabel = km.group(1);
          keptContent = km.group(2);
          break;
        }
      }
      entries.add(ReferenceEntry(
        filePath: relPath,
        label: m.group(1) ?? '',
        body: _stripQuoteBlock(m.group(2) ?? ''),
        keptPreview: keptContent != null
            ? _truncateToPreview(keptContent)
            : _extractKeptPreview(content, m.start),
        matchStart: m.start,
        matchEnd: m.end,
        keptMarkerStart: keptStart,
        keptMarkerEnd: keptEnd,
        keptLabel: keptLabel,
        keptContent: keptContent,
      ));
    }
  }
  return entries;
}

/// Swaps a "kept for reference" leftover back to being the active, kept
/// content in the note - the literal opposite of the pick that created
/// it. Only possible when [entry].keptMarkerStart is non-null - see
/// ReferenceEntry's own doc for why an older, already-resolved note has
/// no exact span to swap and simply can't offer this.
///
/// 2026-08-27: real feedback, live - "just reverted version does not
/// need to be backed up." Unlike deleteReferenceCallout below, this
/// deliberately writes no separate backup file first: the content being
/// displaced isn't discarded, it's written right back into a
/// [!question]- reference callout in the same spot the version now
/// returning used to occupy - exactly as recoverable after Undo as
/// before it, so a second backup of the same text would be redundant.
Future<void> undoReferenceCallout(
  String vaultPath,
  ReferenceEntry entry,
) async {
  if (entry.keptMarkerStart == null || entry.keptLabel == null) return;
  final filePath = '$vaultPath/${entry.filePath}';
  final content = await File(filePath).readAsString();
  if (entry.matchEnd > content.length) return; // file changed since scan

  final matchedSpan = content.substring(entry.matchStart, entry.matchEnd);
  final trailingNewline = matchedSpan.endsWith('\n') ? '\n' : '';

  final newKept = '<!-- LOCALSYNC-KEPT label="${entry.label}" -->\n'
      '${entry.body}\n'
      '<!-- LOCALSYNC-KEPT-END -->\n\n';
  final newRef = _mergeCallout(ConflictVersion(
    who: entry.keptLabel!,
    when: null,
    body: entry.keptContent!,
  ));

  final updated = content.replaceRange(entry.keptMarkerStart!, entry.matchEnd,
      '$newKept$newRef$trailingNewline');
  await VaultFolderService().coordinatedWrite(filePath, updated);
}

/// 2026-09-07: real feedback, live - "phone with data from 2105 and
/// desktop with data from 1500. I want to merge the 1500 before the
/// 2105, but I don't see any options to MERGE or KEEP BOTH." A reference
/// leftover only ever offered Undo (full swap back) or Delete (discard)
/// - no way to combine both, unlike applyKeepBoth's equivalent for a
/// still-open conflict. This is that same fix applied here: replaces
/// the kept marker + reference callout with both texts as plain,
/// unwrapped paragraphs, chronologically ordered when every version has
/// a leading HHMM time (journalOrderedBodies - same rule, same helper).
/// Only possible when entry.keptMarkerStart is non-null, same gate as
/// undoReferenceCallout above - an older note has no exact span for the
/// kept side to safely splice against, only a heuristic preview.
///
/// Pure string transform, no file I/O - same split as applyKeepBoth/
/// applyResolution above.
///
/// 2026-09-18: matches applyKeepBoth's own 2026-09-18 change - no
/// reordering here either, plain arrival-order concatenation.
String applyMergeReference(String content, ReferenceEntry entry) {
  final matchedSpan = content.substring(entry.keptMarkerStart!, entry.matchEnd);
  final trailingNewline = matchedSpan.endsWith('\n') ? '\n' : '';
  final bodies = [entry.keptContent!, entry.body];
  final merged = '${bodies.join('\n\n')}$trailingNewline';
  // 2026-09-14: real feedback, live - same fix as applyResolution/
  // applyKeepBoth above. $merged is plain text, no wrapper, so the
  // default (checkText == replacement) applies directly.
  return repositionedReplace(
      content, entry.keptMarkerStart!, entry.matchEnd, merged);
}

/// Backs up both sides first (same safety convention as every other
/// destructive action in this file), then applies [applyMergeReference].
Future<void> mergeReferenceKeepingBoth(
  String vaultPath,
  ReferenceEntry entry,
) async {
  if (entry.keptMarkerStart == null || entry.keptContent == null) return;
  final backupDir =
      Directory(conflictBackupsDir(vaultPath));
  await backupDir.create(recursive: true);
  final baseName = entry.filePath.split('/').last.replaceAll('.md', '');
  final backupFile =
      File('${backupDir.path}/$baseName - ${backupTimestamp()}.md');
  await backupFile.writeAsString(
    '# Reference content, merged by user\n\n'
    'Original file: ${entry.filePath}\n\n'
    '## Kept\n\n${entry.keptContent}\n\n'
    '## Merged in (from: ${entry.label})\n\n${entry.body}\n',
  );

  final filePath = '$vaultPath/${entry.filePath}';
  final content = await File(filePath).readAsString();
  if (entry.matchEnd > content.length) return; // file changed since scan
  final updated = applyMergeReference(content, entry);
  await VaultFolderService().coordinatedWrite(filePath, updated);
}

/// Removes exactly one reference callout, backing up its content first -
/// same safety convention as resolveConflict below: never silently
/// discard something that was specifically kept so nothing would be
/// lost. Coordinated write for the same Obsidian-cache reason
/// resolveConflict uses it.
Future<void> deleteReferenceCallout(
  String vaultPath,
  ReferenceEntry entry,
) async {
  final backupDir =
      Directory(conflictBackupsDir(vaultPath));
  await backupDir.create(recursive: true);
  final baseName = entry.filePath.split('/').last.replaceAll('.md', '');
  final backupFile =
      File('${backupDir.path}/$baseName - ${backupTimestamp()}.md');
  await backupFile.writeAsString(
    '# Reference content, removed by user\n\n'
    'Original file: ${entry.filePath}\n'
    'From: ${entry.label}\n\n'
    '${entry.body}\n',
  );

  final filePath = '$vaultPath/${entry.filePath}';
  final content = await File(filePath).readAsString();
  if (entry.matchEnd > content.length) return; // file changed since scan
  final updated = content.replaceRange(entry.matchStart, entry.matchEnd, '');
  await VaultFolderService().coordinatedWrite(filePath, updated);
}

/// Rewrites [filePath] (relative to [vaultPath]), replacing exactly the
/// conflict span [entry] was found at with [chosen] (typically
/// entry.ours or entry.theirs, picked by the user). Direct substring
/// replace at known offsets - no re-parsing, no guessing. Always backs
/// up both original versions first (see above) - never called without
/// that safety net in place. Returns the backup file's vault-relative
/// path (see _backupConflictBeforeResolving) so the caller can deep-
/// link straight to it.
Future<String> resolveConflict(
  String vaultPath,
  ConflictEntry entry,
  String chosen,
) async {
  final backupRelPath = await _backupConflictBeforeResolving(vaultPath, entry);
  final filePath = '$vaultPath/${entry.filePath}';
  final content = await File(filePath).readAsString();
  if (entry.matchEnd > content.length)
    return backupRelPath; // file changed since scan
  final keepLeftover = await DatabaseService().getKeepLeftoverInNote();
  final updated =
      applyResolution(content, entry, chosen, keepLeftoverInNote: keepLeftover);
  // 2026-08-19: coordinated (not plain) write - see
  // vault_folder_service.dart's coordinatedWrite for why: a resolution
  // written the plain way was found silently reverted by Obsidian's own
  // cache on a real device, this is the best-available fix, unconfirmed
  // on device.
  await VaultFolderService().coordinatedWrite(filePath, updated);
  return backupRelPath;
}

/// 2026-09-07: real feedback, live - "the app is supposed to fix" a
/// conflict like two unrelated real journal entries (this user's real
/// case: a 2105 entry and an untimed one, both genuinely belonging in
/// the note) landing as a conflict. Every existing action either kept
/// one side and demoted the other to a collapsed reference callout
/// (resolveConflict/applyResolution) or required manually assembling
/// pieces sentence-by-sentence (MergePickerScreen, the paid put/yank
/// tier) - neither is a one-tap "both belong here" fix. This is that
/// fix: replaces the whole conflict span with every version's body as
/// plain, unwrapped text - nothing left "unresolved," nothing collapsed
/// into a reference - ordered chronologically when every version has a
/// leading HHMM time (conflict_repair.dart's journalOrderedBodies,
/// the same rule the write side already uses when it can safely apply
/// this automatically), in original stacking order otherwise. Always
/// backs up every version first, same safety net as resolveConflict -
/// this never discards anything, it only changes how it's displayed.
///
/// Pure string transform, no file I/O - same split as
/// applyResolution/resolveConflict above, so this is unit-testable
/// directly (see test/conflict_scanner_test.dart).
// 2026-09-15: real feedback, live - "the app... Obsidian output is not
// normal" turned out to have no real fix on the Obsidian side (no
// Live Preview/Source toggle was findable on the device this was hit
// on) - decided instead to stop wrapping Keep Both's undo data in note
// text at all. Undo state now lives in the app's own local database
// (see KeptBothRecord + DatabaseService.getKeptBothRecords below);
// applyKeepBoth writes plain merged text with zero wrapper, so there's
// nothing left for Obsidian to ever render wrong. _decodeKeptBothData
// and the two patterns below are kept read-only, forever - real notes
// already have the old inline markers sitting in them, and Undo must
// keep working on those without a migration step no user would ever
// run.
List<ConflictVersion> _decodeKeptBothData(String encoded) {
  final data = jsonDecode(utf8.decode(base64Decode(encoded))) as List;
  return data
      .map((e) => ConflictVersion(
          who: e['who'] as String,
          when: e['when'] as String?,
          body: e['body'] as String))
      .toList();
}

// 2026-09-09: legacy pattern for notes written when this app still
// wrapped Keep Both's undo data in a %% ... %% marker (see 2026-09-15's
// comment above for why that stopped) - kept read-only, same reasoning
// as _keptBothPatternLegacy just below: Undo must keep working on
// already-real notes, forever, not just the ones resolved after the
// database switch.
final _keptBothPattern = RegExp(
  r'%% LOCALSYNC-KEPTBOTH data="(.*?)" %%\n(.*?)\n%% LOCALSYNC-KEPTBOTH-END %%\n?',
  dotAll: true,
);
// 2026-09-09: legacy pattern for notes already written with the old
// <!-- --> wrapper before the %% switch above - kept read-only (never
// written again) so Undo still works on anything resolved before this
// fix shipped, instead of silently losing that capability for
// already-real notes.
final _keptBothPatternLegacy = RegExp(
  r'<!-- LOCALSYNC-KEPTBOTH data="(.*?)" -->\n(.*?)\n<!-- LOCALSYNC-KEPTBOTH-END -->\n?',
  dotAll: true,
);

/// Rebuilds a SYNC CONFLICT block from [versions], in the exact shape
/// scanForConflicts' own patterns expect - same header/kind/label
/// convention conflict_repair.dart's write side uses (index 0 is
/// "yours"/!info, every other version is !warning), so an undone Keep
/// Both re-enters the Conflicts list as a real, resolvable conflict
/// again, not a dead end.
String _rebuildConflictBlock(List<ConflictVersion> versions) {
  final blocks = <String>[];
  for (var i = 0; i < versions.length; i++) {
    final kind = i == 0 ? '!info' : '!warning';
    final label = i == 0
        ? 'yours'
        : (versions[i].when != null
            ? '${versions[i].who} - ${versions[i].when}'
            : versions[i].who);
    final quoted = versions[i].body.split('\n').map((l) => '> $l').join('\n');
    blocks.add('> [$kind]- SYNC CONFLICT - $label (review and delete one) - '
        'open LocalSync → ⋮ → Conflicts\n$quoted');
  }
  return '${blocks.join('\n')}\n';
}

/// Pure string transform - the caller (mergeConflictKeepingBoth) is the
/// one that persists a KeptBothRecord for undo, since that's real I/O
/// and this stays unit-testable directly (see
/// test/conflict_scanner_test.dart).
class KeepBothResult {
  final String content;
  final String mergedText;
  const KeepBothResult(this.content, this.mergedText);
}

// 2026-09-16: [cleanUp] is the Tier 3 IAP addition
// (kKeepBothCleanupEntitlementId, docs/product-tiers.md) - false (the
// default) keeps free KEEP BOTH's existing, honest behavior: a plain
// concatenate in arrival order. true swaps in journalOrderedEntries'
// paragraph-level interleave instead, for real cross-body chronological
// ordering.
//
// 2026-09-18: real ask, live - "Keep both text: not reordered entry by
// entry. Just, not reordered." Free KEEP BOTH used to still run
// journalOrderedBodies (a whole-body chronological sort) even without
// Clean Up - explicitly reverted per this ask, at the cost of possibly
// reintroducing the 2026-09-16 "text with clock is out of order" report
// for free-tier users who don't buy Clean Up. User's own tradeoff to
// make, confirmed when asked.
KeepBothResult applyKeepBoth(String content, ConflictEntry entry,
    {bool cleanUp = false}) {
  final rawBodies = entry.versions.map((v) => v.body).toList();
  final bodies = cleanUp ? journalOrderedEntries(rawBodies) : rawBodies;
  final merged = bodies.join('\n\n');
  // 2026-09-15: no wrapper marker written any more (see the comment
  // above _decodeKeptBothData) - the merged text goes into the note
  // exactly as a plain resolution would, and undo state for it lives
  // in the local database instead.
  // 2026-09-14: real feedback, live - same fix as applyResolution
  // above, checking $merged's own leading time to place it correctly.
  final updated = repositionedReplace(
      content, entry.matchStart, entry.matchEnd, merged,
      timeCheckText: merged);
  return KeepBothResult(updated, merged);
}

class KeptBothEntry {
  final String filePath; // relative to the vault root
  final List<ConflictVersion> versions;
  final int matchStart;
  final int matchEnd;
  // Set only for entries backed by a KeptBothRecord in the local
  // database (post 2026-09-15) - null for legacy inline-marker entries,
  // whose matchStart/matchEnd already span the whole marker block and
  // need nothing else to undo. See undoKeepBoth.
  final String? dbId;
  const KeptBothEntry({
    required this.filePath,
    required this.versions,
    required this.matchStart,
    required this.matchEnd,
    this.dbId,
  });
}

/// Persisted record of a Keep Both resolution written with no inline
/// marker (see 2026-09-15's comment above _decodeKeptBothData) - this
/// is the undo data that used to live in the note itself. [mergedText]
/// is the exact text applyKeepBoth wrote into the note; since nothing
/// else in a real vault would coincidentally produce that literal
/// string, scanForKeptBoth relocates it with a plain indexOf rather
/// than needing any marker to search for.
class KeptBothRecord {
  final String id;
  final String filePath; // relative to the vault root
  final List<ConflictVersion> versions;
  final String mergedText;
  final DateTime resolvedAt;
  const KeptBothRecord({
    required this.id,
    required this.filePath,
    required this.versions,
    required this.mergedText,
    required this.resolvedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'filePath': filePath,
        'versions': versions
            .map((v) => {'who': v.who, 'when': v.when, 'body': v.body})
            .toList(),
        'mergedText': mergedText,
        'resolvedAt': resolvedAt.toIso8601String(),
      };

  factory KeptBothRecord.fromJson(Map<String, dynamic> json) => KeptBothRecord(
        id: json['id'] as String,
        filePath: json['filePath'] as String,
        versions: (json['versions'] as List<dynamic>)
            .map((e) => ConflictVersion(
                who: e['who'] as String,
                when: e['when'] as String?,
                body: e['body'] as String))
            .toList(),
        mergedText: json['mergedText'] as String,
        resolvedAt: DateTime.parse(json['resolvedAt'] as String),
      );
}

Future<List<KeptBothRecord>> _loadKeptBothRecords() async {
  final raw = await DatabaseService().getKeptBothRecords();
  return raw.map(KeptBothRecord.fromJson).toList();
}

Future<void> _saveKeptBothRecord(KeptBothRecord record) async {
  final records = await _loadKeptBothRecords();
  records.add(record);
  await DatabaseService()
      .setKeptBothRecords(records.map((r) => r.toJson()).toList());
}

Future<void> _deleteKeptBothRecord(String id) async {
  final records = await _loadKeptBothRecords();
  records.removeWhere((r) => r.id == id);
  await DatabaseService()
      .setKeptBothRecords(records.map((r) => r.toJson()).toList());
}

/// Finds every "Keep Both" resolution still sitting in the vault -
/// same walk/exclusion pattern as scanForReferenceCallouts. Available
/// indefinitely, same as that Undo - the marker is invisible in
/// reading view, so there's no clutter forcing a cleanup step the way
/// a collapsed reference callout does.
void _collectLegacyKeptBothMarkers(
    String content, String relPath, List<KeptBothEntry> entries) {
  for (final m in [
    ..._keptBothPattern.allMatches(content),
    ..._keptBothPatternLegacy.allMatches(content),
  ]) {
    List<ConflictVersion> versions;
    try {
      versions = _decodeKeptBothData(m.group(1)!);
    } catch (_) {
      continue; // corrupted/foreign marker - skip rather than crash
    }
    entries.add(KeptBothEntry(
      filePath: relPath,
      versions: versions,
      matchStart: m.start,
      matchEnd: m.end,
    ));
  }
}

Future<List<KeptBothEntry>> scanForKeptBoth(String vaultPath) async {
  final entries = <KeptBothEntry>[];
  final dir = Directory(vaultPath);
  if (!await dir.exists()) return entries;
  final skipFolders = localSyncFolders(vaultPath);

  // 2026-09-15: two sources now - legacy inline markers still sitting
  // in already-real notes (read-only, see _decodeKeptBothData's
  // comment), and KeptBothRecord entries in the local database for
  // everything resolved since. recordsByFile lets the walk below check
  // both per file with one read, instead of two separate passes.
  final records = await _loadKeptBothRecords();
  final recordsByFile = <String, List<KeptBothRecord>>{};
  for (final r in records) {
    recordsByFile.putIfAbsent(r.filePath, () => []).add(r);
  }
  final staleIds = <String>[];

  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.md')) continue;
    if (entity.path.contains('/$kLocalSyncFolderName/')) continue;
    if (isInLocalSyncFolder(
        entity.path.substring(vaultPath.length + 1), skipFolders)) {
      continue;
    }
    if (entity.path.contains('/LocalSync Conflict Backups/')) continue;
    if (entity.path.contains('/LocalSync Vault Backup ')) continue;

    final relPath = entity.path.substring(vaultPath.length + 1);
    final fileRecords = recordsByFile[relPath];
    if (fileRecords == null) {
      final content = await entity.readAsString();
      if (!content.contains('LOCALSYNC-KEPTBOTH')) continue;
      _collectLegacyKeptBothMarkers(content, relPath, entries);
      continue;
    }

    final content = await entity.readAsString();
    if (content.contains('LOCALSYNC-KEPTBOTH')) {
      _collectLegacyKeptBothMarkers(content, relPath, entries);
    }
    for (final r in fileRecords) {
      final idx = content.indexOf(r.mergedText);
      if (idx < 0) {
        staleIds.add(r.id); // merged text edited/removed - nothing to undo
        continue;
      }
      entries.add(KeptBothEntry(
        filePath: relPath,
        versions: r.versions,
        matchStart: idx,
        matchEnd: idx + r.mergedText.length,
        dbId: r.id,
      ));
    }
  }

  if (staleIds.isNotEmpty) {
    final remaining = records.where((r) => !staleIds.contains(r.id)).toList();
    await DatabaseService()
        .setKeptBothRecords(remaining.map((r) => r.toJson()).toList());
  }

  return entries;
}

/// Swaps a Keep Both resolution back to being an active, resolvable
/// SYNC CONFLICT - the literal opposite of the merge that created it.
/// Writes no separate backup first, same reasoning as
/// undoReferenceCallout: nothing is discarded, the exact original
/// content is simply restored from the marker's own embedded data.
Future<void> undoKeepBoth(String vaultPath, KeptBothEntry entry) async {
  final filePath = '$vaultPath/${entry.filePath}';
  final content = await File(filePath).readAsString();
  if (entry.matchEnd > content.length) return; // file changed since scan
  final rebuilt = _rebuildConflictBlock(entry.versions);
  final updated =
      content.replaceRange(entry.matchStart, entry.matchEnd, rebuilt);
  await VaultFolderService().coordinatedWrite(filePath, updated);
  // 2026-09-15: only set for database-backed entries (see KeptBothEntry)
  // - a legacy inline marker's undo data lived in the marker text
  // itself, already fully removed by the replaceRange above.
  if (entry.dbId != null) {
    await _deleteKeptBothRecord(entry.dbId!);
  }
}

/// 2026-09-26: Ken - "MERGE TEXT ... build in a UNDO as well". The whole
/// note before and after a MERGE TEXT resolution, so the success banner
/// can put it back in one tap.
class MergeUndo {
  final String filePath; // relative to the vault
  final String before;
  final String after;
  const MergeUndo(this.filePath, this.before, this.after);
}

/// Puts the note back exactly as it was before MERGE TEXT. Returns false
/// (and writes nothing) if the note changed since the merge - never
/// overwrite newer edits.
Future<bool> undoMerge(String vaultPath, MergeUndo undo) async {
  final file = File('$vaultPath/${undo.filePath}');
  if (await file.readAsString() != undo.after) return false;
  await VaultFolderService().coordinatedWrite(file.path, undo.before);
  return true;
}

Future<String> mergeConflictKeepingBoth(
  String vaultPath,
  ConflictEntry entry, {
  bool cleanUp = false,
}) async {
  final backupRelPath = await _backupConflictBeforeResolving(vaultPath, entry);
  final filePath = '$vaultPath/${entry.filePath}';
  final content = await File(filePath).readAsString();
  if (entry.matchEnd > content.length)
    return backupRelPath; // file changed since scan
  final result = applyKeepBoth(content, entry, cleanUp: cleanUp);
  await VaultFolderService().coordinatedWrite(filePath, result.content);
  await _saveKeptBothRecord(KeptBothRecord(
    id: '${entry.filePath}#${DateTime.now().microsecondsSinceEpoch}',
    filePath: entry.filePath,
    versions: entry.versions,
    mergedText: result.mergedText,
    resolvedAt: DateTime.now(),
  ));
  return backupRelPath;
}
