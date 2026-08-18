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

class ConflictEntry {
  final String filePath; // relative to the vault root
  final String ours;
  final String theirs;
  final String who;
  final String? when;
  final bool isKanban;
  final int matchStart;
  final int matchEnd;
  const ConflictEntry({
    required this.filePath,
    required this.ours,
    required this.theirs,
    required this.who,
    this.when,
    required this.isKanban,
    required this.matchStart,
    required this.matchEnd,
  });
}

final _pairedCalloutPattern = RegExp(
  r'> \[!info\]\+ SYNC CONFLICT — yours \(review and delete one\)\n'
  r'((?:> .*\n?)*)'
  r'\n?'
  r'> \[!warning\]\+ SYNC CONFLICT — (.+?) \(review and delete one\)\n'
  r'((?:> .*\n?)*)',
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
        final who = commentLines.first.group(1)!;
        final theirsText =
            commentLines.map((c) => c.group(2)!).join('\n');
        entries.add(ConflictEntry(
          filePath: relPath,
          ours: oursLine,
          theirs: theirsText,
          who: who,
          isKanban: true,
          matchStart: m.start,
          matchEnd: m.end,
        ));
      }
    } else {
      for (final m in _pairedCalloutPattern.allMatches(content)) {
        final rawLabel = m.group(2)!;
        final sep = rawLabel.indexOf(' — ');
        entries.add(ConflictEntry(
          filePath: relPath,
          ours: _stripQuoteBlock(m.group(1)!),
          theirs: _stripQuoteBlock(m.group(3)!),
          who: sep == -1 ? rawLabel : rawLabel.substring(0, sep),
          when: sep == -1 ? null : rawLabel.substring(sep + 3),
          isKanban: false,
          matchStart: m.start,
          matchEnd: m.end,
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
/// recoverable - this does. Both full versions get written to a plain
/// Obsidian note before the file is touched, so whichever side gets
/// discarded is still sitting in the vault afterward, in plain text, no
/// git knowledge required to find it.
Future<void> _backupConflictBeforeResolving(
  String vaultPath,
  ConflictEntry entry,
) async {
  final backupDir = Directory('$vaultPath/LocalSync Conflict Backups');
  await backupDir.create(recursive: true);
  final baseName = entry.filePath.split('/').last.replaceAll('.md', '');
  final backupFile =
      File('${backupDir.path}/$baseName - ${backupTimestamp()}.md');
  final theirsHeading =
      entry.when != null ? '${entry.who} - ${entry.when}' : entry.who;
  await backupFile.writeAsString(
    '# Conflict backup\n\n'
    'Original file: ${entry.filePath}\n\n'
    '## Your version\n\n'
    '${entry.ours}\n\n'
    '## $theirsHeading\n\n'
    '${entry.theirs}\n',
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
  final file = File('$vaultPath/${entry.filePath}');
  final content = await file.readAsString();
  if (entry.matchEnd > content.length) return; // file changed since scan
  final replacement = entry.isKanban ? chosen : '$chosen\n';
  final updated = content.replaceRange(
      entry.matchStart, entry.matchEnd, replacement);
  await file.writeAsString(updated);
}
