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

import 'dart:io';
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
final _stackedBlockPattern = RegExp(
  r'(?:> \[!(?:info|warning)\]\+ SYNC CONFLICT [-—] .+? \(review and delete one\)\n'
  r'(?:> (?!\[!(?:info|warning)\]\+ SYNC CONFLICT).*\n?)*\n?)+',
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
  r'> \[!(?:info|warning)\]\+ SYNC CONFLICT [-—] (.+?) \(review and delete one\)\n'
  r'((?:> (?!\[!(?:info|warning)\]\+ SYNC CONFLICT).*\n?)*)',
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
    if (relPath.startsWith('$kLocalSyncFolderName/') ||
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
      Directory('$vaultPath/$kLocalSyncFolderName/Conflict Backups');
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
  return '$kLocalSyncFolderName/Conflict Backups/$backupFileName';
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
String applyResolution(String content, ConflictEntry entry, String chosen) {
  final matchedSpan = content.substring(entry.matchStart, entry.matchEnd);
  final trailingNewline = matchedSpan.endsWith('\n') ? '\n' : '';
  final notChosen =
      entry.versions.where((v) => v.body != chosen).toList();
  String merged;
  if (entry.isKanban || notChosen.isEmpty) {
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
  return content.replaceRange(entry.matchStart, entry.matchEnd, replacement);
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
  final tail =
      text.length <= _maxLookback ? text : text.substring(text.length - _maxLookback);
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

  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.md')) continue;
    if (entity.path.contains('/$kLocalSyncFolderName/')) continue;
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

  final updated = content.replaceRange(
      entry.keptMarkerStart!, entry.matchEnd, '$newKept$newRef$trailingNewline');
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
      Directory('$vaultPath/$kLocalSyncFolderName/Conflict Backups');
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
  if (entry.matchEnd > content.length) return backupRelPath; // file changed since scan
  final updated = applyResolution(content, entry, chosen);
  // 2026-08-19: coordinated (not plain) write - see
  // vault_folder_service.dart's coordinatedWrite for why: a resolution
  // written the plain way was found silently reverted by Obsidian's own
  // cache on a real device, this is the best-available fix, unconfirmed
  // on device.
  await VaultFolderService().coordinatedWrite(filePath, updated);
  return backupRelPath;
}
