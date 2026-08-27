// services/binary_conflict_log.dart
//
// 2026-08-27: sync_service.dart's repairBinaryConflictsOnDisk auto-keeps
// "ours" for any conflict on a non-.md file (real content can't be
// text-merged or wrapped in a markdown callout the way conflict_scanner
// .dart does) - a safe default, not a guess, since both sides are always
// backed up first. But a safe default still isn't a real choice - the
// markdown path lets the user pick either side (conflict_picker_screen
// .dart) and undo a pick (conflict_scanner.dart's undoReferenceCallout).
// This is that same choice for whole files, minus the inline markers a
// markdown note can carry: nothing about a binary file's own bytes can
// record "here's the other version" the way an HTML comment does in a
// .md note, so this keeps a small on-disk log instead - one JSON object
// per resolved binary conflict, in the same Conflict Backups folder the
// backup files themselves already live in.
//
// Deliberately NOT reusing conflict_scanner.dart's ReferenceEntry/
// undoReferenceCallout shape - those are anchored to exact byte offsets
// inside a specific note's text content, which has no equivalent here.

import 'dart:convert';
import 'dart:io';
import 'vault_backup.dart';

const _logFileName = 'binary_conflicts.json';

class BinaryConflictLogEntry {
  final String path; // vault-relative
  final String keptBackupName; // filename only, inside Conflict Backups/
  final String otherBackupName;
  final String otherLabel;
  final String when; // backupTimestamp() format, YYYYMMDDhhmm

  const BinaryConflictLogEntry({
    required this.path,
    required this.keptBackupName,
    required this.otherBackupName,
    required this.otherLabel,
    required this.when,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'keptBackupName': keptBackupName,
        'otherBackupName': otherBackupName,
        'otherLabel': otherLabel,
        'when': when,
      };

  factory BinaryConflictLogEntry.fromJson(Map<String, dynamic> m) =>
      BinaryConflictLogEntry(
        path: m['path'] as String,
        keptBackupName: m['keptBackupName'] as String,
        otherBackupName: m['otherBackupName'] as String,
        otherLabel: m['otherLabel'] as String,
        when: m['when'] as String,
      );
}

File _logFile(String vaultPath) =>
    File('$vaultPath/$kLocalSyncFolderName/Conflict Backups/$_logFileName');

/// Appends one resolved-binary-conflict record. Read-modify-write of a
/// small JSON array - conflicts on distinct files land as distinct
/// entries; this isn't called concurrently within one pull (the caller,
/// repairBinaryConflictsOnDisk, runs single-threaded per conflict).
void appendBinaryConflictLogEntry(String vaultPath, BinaryConflictLogEntry entry) {
  final file = _logFile(vaultPath);
  final existing = _readAll(file);
  existing.add(entry);
  file.writeAsStringSync(jsonEncode(existing.map((e) => e.toJson()).toList()));
}

List<BinaryConflictLogEntry> _readAll(File file) {
  if (!file.existsSync()) return [];
  try {
    final raw = jsonDecode(file.readAsStringSync()) as List<dynamic>;
    return raw
        .map((m) => BinaryConflictLogEntry.fromJson(m as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return []; // corrupt/unreadable log - treat as empty, never crash a scan
  }
}

/// Every whole-file conflict currently sitting at its safe "kept ours"
/// default, still swappable to the other side.
List<BinaryConflictLogEntry> scanBinaryConflictLog(String vaultPath) =>
    _readAll(_logFile(vaultPath));

/// Swaps the live file to the other backed-up side, then drops this
/// entry from the log - the same convention conflict_scanner.dart's
/// undoReferenceCallout uses: no new backup made on swap, since the
/// side being displaced is already sitting in Conflict Backups under
/// [entry.keptBackupName] and stays exactly as recoverable as it was
/// before. A second swap is possible by hand from the backups folder,
/// even though the log entry itself is single-use once acted on.
void swapBinaryConflict(String vaultPath, BinaryConflictLogEntry entry) {
  final backupDir = '$vaultPath/$kLocalSyncFolderName/Conflict Backups';
  final otherBytes = File('$backupDir/${entry.otherBackupName}').readAsBytesSync();
  File('$vaultPath/${entry.path}').writeAsBytesSync(otherBytes);

  final all = _readAll(_logFile(vaultPath));
  all.removeWhere((e) =>
      e.path == entry.path &&
      e.keptBackupName == entry.keptBackupName &&
      e.when == entry.when);
  _logFile(vaultPath)
      .writeAsStringSync(jsonEncode(all.map((e) => e.toJson()).toList()));
}

/// Dismisses a log entry without changing the live file - "I've seen
/// this, keeping what's already there." Distinct from swapBinaryConflict:
/// this never touches the working file, only stops listing it.
void dismissBinaryConflictLogEntry(String vaultPath, BinaryConflictLogEntry entry) {
  final all = _readAll(_logFile(vaultPath));
  all.removeWhere((e) =>
      e.path == entry.path &&
      e.keptBackupName == entry.keptBackupName &&
      e.when == entry.when);
  _logFile(vaultPath)
      .writeAsStringSync(jsonEncode(all.map((e) => e.toJson()).toList()));
}
