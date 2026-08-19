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
    // non-already-empty folder gets a "LocalSync Vault Backup
    // <timestamp>" snapshot (see vault_backup.dart) that can contain
    // old, already-stale conflict markers from before. Scanning inside
    // backup folders surfaced those as live, actionable conflicts -
    // confusing and wrong, since resolving a snapshot of the past
    // isn't a real action. Same reasoning excludes this scanner's own
    // "LocalSync Conflict Backups" output from being re-scanned as a
    // conflict, though that one's format doesn't match the callout
    // patterns below anyway.
    final relPath = entity.path.replaceFirst('${dir.path}/', '');
    if (relPath.startsWith('LocalSync Vault Backup ') ||
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
Future<void> _backupConflictBeforeResolving(
  String vaultPath,
  ConflictEntry entry,
) async {
  final backupDir = Directory('$vaultPath/LocalSync Conflict Backups');
  await backupDir.create(recursive: true);
  final baseName = entry.filePath.split('/').last.replaceAll('.md', '');
  final backupFile =
      File('${backupDir.path}/$baseName - ${backupTimestamp()}.md');
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
}

/// Rewrites [filePath] (relative to [vaultPath]), replacing exactly the
/// conflict span [entry] was found at with [chosen] (typically
/// entry.ours or entry.theirs, picked by the user). Direct substring
/// replace at known offsets - no re-parsing, no guessing. Always backs
/// up both original versions first (see above) - never called without
/// that safety net in place.
Future<void> resolveConflict(
  String vaultPath,
  ConflictEntry entry,
  String chosen,
) async {
  await _backupConflictBeforeResolving(vaultPath, entry);
  final filePath = '$vaultPath/${entry.filePath}';
  final content = await File(filePath).readAsString();
  if (entry.matchEnd > content.length) return; // file changed since scan
  final replacement = entry.isKanban ? chosen : '$chosen\n';
  final updated = content.replaceRange(
      entry.matchStart, entry.matchEnd, replacement);
  // 2026-08-19: coordinated (not plain) write - see
  // vault_folder_service.dart's coordinatedWrite for why: a resolution
  // written the plain way was found silently reverted by Obsidian's own
  // cache on a real device, this is the best-available fix, unconfirmed
  // on device.
  await VaultFolderService().coordinatedWrite(filePath, updated);
}
