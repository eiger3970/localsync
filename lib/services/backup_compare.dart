// services/backup_compare.dart
//
// 2026-09-06: real feedback, live - "why paste manually, why not a
// picker for this too?" This app already has a real visual word-diff
// picker (conflict_picker_screen.dart) - tap either panel to keep a
// whole side, no manual retyping - but it only ever turns on for a
// conflict the app itself detected via marker parsing inside one file.
// A recovery from an already-lost divergence (this session's real
// incident) has no such marker - the "other version" lives in a
// separate backup file, not embedded in the live note. This lets a
// user manually pick any file from LocalSync/Conflict Backups and
// compare it against its real live note in that same picker style,
// instead of reading both and retyping by hand.
//
// Pure logic only, no dart:io/Flutter - the actual file reads and
// vault walk live in backup_compare_screen.dart, same split
// conflict_repair.dart already uses (pure logic vs. the screens that
// call it) so this part is unit-testable on its own.

/// Every real label sync_service.dart's backupFilesAboutToChange and
/// the manual-combine fallback ever write into a backup filename (see
/// that file's own _conflictBackupName). Kept here as the single known
/// vocabulary a backup filename can contain, rather than guessing at a
/// generic "name - anything - anything" pattern, which would be
/// ambiguous the moment a real note name itself contains " - ".
const knownBackupLabels = [
  'before auto-merge, phone version',
  'before auto-merge, desktop version',
  'desktop version',
  'before pull reset',
  'before push-retry reset',
];

final _timestampPattern = RegExp(r'^\d{12}(\.[^.]*)?$');

/// Recovers the original note's filename from a Conflict Backups
/// filename, reversing sync_service.dart's _conflictBackupName format
/// ("$stem - $label - $ts$ext"). Returns null if the name doesn't
/// match any known label at all (a file a user dropped into this
/// folder by hand, for instance, or a future label this list hasn't
/// been updated for yet) - callers should treat that as "can't offer
/// compare for this one," never guess.
String? originalFileNameFromBackup(String backupFileName) {
  for (final label in knownBackupLabels) {
    final marker = ' - $label - ';
    final idx = backupFileName.indexOf(marker);
    if (idx == -1) continue;
    final stem = backupFileName.substring(0, idx);
    if (stem.isEmpty) continue;
    final afterLabel = backupFileName.substring(idx + marker.length);
    final match = _timestampPattern.firstMatch(afterLabel);
    if (match == null) continue;
    final ext = match.group(1) ?? '';
    return '$stem$ext';
  }
  return null;
}

/// Given every real note path in the vault (vault-relative, '/'-
/// separated), finds the ones whose filename (last path segment)
/// matches [originalFileName] exactly. More than one match is
/// realistic (two folders can both hold a note with the same name) -
/// callers must not guess between them, only proceed automatically on
/// exactly one match.
List<String> matchingLivePaths(
    List<String> allVaultPaths, String originalFileName) {
  return allVaultPaths
      .where((p) => p.split('/').last == originalFileName)
      .toList();
}
