// services/localsync_cleanup.dart
//
// 2026-09-29: Ken - "Some help with cleaning up Obsidian from the LocalSync
// folder mess" ... "I like to optimise [my phone's] performance." Lists the
// safety-copy folders inside every LocalSync folder of a synced folder, with
// file count and size, and removes them all except the newest "Backup
// <date>". Only folders inside LocalSync folders are ever touched - the
// user's own notes never are - and every removed file stays in the desktop's
// history (Restore deleted files).
import 'dart:io';
import 'localsync_folder.dart';
import 'vault_backup.dart' show kFullBackupsFolder;

class BackupFolder {
  final String relPath; // vault-relative, e.g. LocalSync/Conflict Backups
  final int files;
  final int bytes;
  final bool keep; // the newest "Backup <date>" - never cleaned up
  const BackupFolder(this.relPath, this.files, this.bytes, {this.keep = false});
  String get name => relPath.split('/').last;
  /// 2026-09-30: a full copy in kFullBackupsFolder - never synced, so this
  /// phone holds the only copy. Always kept. (Conflict Backups there can
  /// still be cleaned - both sides of every conflict stay in the sync
  /// history, and they're pruned after 30 days anyway.)
  bool get phoneOnly =>
      relPath.startsWith('$kFullBackupsFolder/') &&
      RegExp(r'^(Vault )?Backup \d{12}').hasMatch(name);
}

/// Every folder directly inside a LocalSync folder, alphabetical.
List<BackupFolder> listBackupFolders(String vaultPath) {
  final found = <({String rel, int files, int bytes})>[];
  for (final lsf in localSyncFolders(vaultPath)) {
    final dir = Directory('$vaultPath/$lsf');
    if (!dir.existsSync()) continue;
    for (final e in dir.listSync()) {
      if (e is! Directory) continue;
      final name = e.path.split('/').last;
      if (name.startsWith('.')) continue;
      var files = 0, bytes = 0;
      for (final f in e.listSync(recursive: true, followLinks: false)) {
        if (f is File) {
          files++;
          bytes += f.lengthSync();
        }
      }
      found.add((rel: '$lsf/$name', files: files, bytes: bytes));
    }
  }
  // Newest "Backup <yyyymmddhhmm>" by its timestamp (names sort by time).
  final backups = found
      .where((f) => RegExp(r'^Backup \d{12}$').hasMatch(f.rel.split('/').last))
      .map((f) => f.rel)
      .toList()
    ..sort((a, b) => a.split('/').last.compareTo(b.split('/').last));
  final newest = backups.isEmpty ? null : backups.last;
  return [
    for (final f in found)
      BackupFolder(f.rel, f.files, f.bytes,
          keep: f.rel == newest ||
              BackupFolder(f.rel, 0, 0).phoneOnly),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

/// Removes every folder in [folders] not marked keep. Returns bytes freed.
int cleanUpBackupFolders(String vaultPath, List<BackupFolder> folders) {
  var freed = 0;
  final lsfs = localSyncFolders(vaultPath);
  for (final f in folders) {
    if (f.keep || !isInLocalSyncFolder(f.relPath, lsfs)) continue;
    final dir = Directory('$vaultPath/${f.relPath}');
    if (!dir.existsSync()) continue;
    dir.deleteSync(recursive: true);
    freed += f.bytes;
  }
  return freed;
}

String formatBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).round()} KB';
  if (b < 1024 * 1024 * 1024) return '${(b / (1024 * 1024)).round()} MB';
  return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
