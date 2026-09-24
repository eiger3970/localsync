// services/localsync_folder.dart
//
// 2026-09-24: real feedback, live - "Desktop Obsidian shows a LocalSync
// folder again, but should be in Projects/". The folder was moved by
// hand to Projects/LocalSync on 2026-09-17; the app recreated it at the
// vault's top level the same day, because every backup path was built
// from the fixed kLocalSyncFolderName. Moving it by hand could never
// stick.
//
// Where the folder lives is now a per-vault setting, stored IN the vault
// as one hidden line-of-text file (.localsync_folder at the top level).
// In the vault, not in app preferences, because every device has to
// agree on it: the file syncs like any other content, so the phone,
// the desktop script (localsync_sync.sh reads the same file) and any
// second phone all write to the same place. Hidden (leading dot), so
// Obsidian's file list never shows it - the whole point is less
// top-level clutter, not a different item in the same spot.
//
// No file, an empty file or an unsafe value all mean the default
// kLocalSyncFolderName - existing vaults behave exactly as before.
//
// Plain top-level functions and dart:io sync reads only - safe to call
// from an isolate (sync_service.dart's pull runs in one), same as
// vault_backup.dart.

import 'dart:io';

import 'vault_backup.dart' show kLocalSyncFolderName;

/// Hidden file at the vault's top level holding the folder's
/// vault-relative path, e.g. "Projects/LocalSync".
const kLocalSyncFolderFile = '.localsync_folder';

/// Last folder any call resolved - for UI text that names the folder
/// ("saved to LocalSync/Conflict Backups") but has no vault path in
/// hand at build time. Always a real resolved value or the default.
String lastKnownLocalSyncFolder = kLocalSyncFolderName;

/// Cleans a user-typed folder path into a safe vault-relative one, or
/// returns null if it can't be made safe. Rejects anything that could
/// point outside the vault ("..", absolute paths) or into git's own
/// metadata (".git"), and hidden segments generally - a hidden folder
/// would defeat the "find your backups in Obsidian" point of having a
/// visible one.
String? sanitizeLocalSyncFolder(String raw) {
  final trimmed = raw.trim().replaceAll('\\', '/');
  if (trimmed.isEmpty || trimmed.startsWith('/')) return null;
  final segments = trimmed
      .split('/')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (segments.isEmpty) return null;
  for (final s in segments) {
    if (s == '.' || s == '..' || s.startsWith('.')) return null;
  }
  return segments.join('/');
}

/// The LocalSync folder for [vaultPath], vault-relative (no leading or
/// trailing slash). Reads .localsync_folder; falls back to the default
/// on any problem. Never throws.
String localSyncFolder(String vaultPath) {
  var folder = kLocalSyncFolderName;
  try {
    final file = File('$vaultPath/$kLocalSyncFolderFile');
    if (file.existsSync()) {
      final firstLine = file.readAsLinesSync().firstWhere(
          (l) => l.trim().isNotEmpty,
          orElse: () => '');
      folder = sanitizeLocalSyncFolder(firstLine) ?? kLocalSyncFolderName;
    }
  } catch (_) {
    folder = kLocalSyncFolderName;
  }
  lastKnownLocalSyncFolder = folder;
  return folder;
}

/// "<folder>/Conflict Backups" for [vaultPath], vault-relative.
String conflictBackupsRelPath(String vaultPath) =>
    '${localSyncFolder(vaultPath)}/Conflict Backups';

/// Absolute path of [vaultPath]'s Conflict Backups folder.
String conflictBackupsDir(String vaultPath) =>
    '$vaultPath/${conflictBackupsRelPath(vaultPath)}';

/// Every vault-relative folder LocalSync may have written into: the
/// configured one plus the default, since backups written before the
/// setting changed stay where they are (never moved automatically -
/// they're the user's safety copies). Scanners and verifiers skip all
/// of them.
List<String> localSyncFolders(String vaultPath) {
  final configured = localSyncFolder(vaultPath);
  return configured == kLocalSyncFolderName
      ? [kLocalSyncFolderName]
      : [configured, kLocalSyncFolderName];
}

/// True if [relPath] (vault-relative) sits inside any LocalSync folder.
bool isInLocalSyncFolder(String relPath, List<String> folders) =>
    folders.any((f) => relPath == f || relPath.startsWith('$f/'));

/// Saves [folder] as [vaultPath]'s LocalSync folder. Returns the
/// cleaned value written, or null if [folder] was rejected (nothing is
/// written then). Writing the default removes nothing - it just writes
/// the default, so every device still reads the same explicit value.
String? setLocalSyncFolder(String vaultPath, String folder) {
  final clean = sanitizeLocalSyncFolder(folder);
  if (clean == null) return null;
  File('$vaultPath/$kLocalSyncFolderFile').writeAsStringSync('$clean\n');
  lastKnownLocalSyncFolder = clean;
  return clean;
}

/// repo-name.txt from the configured folder, falling back to the default
/// folder (vaults linked before the setting existed). Null if neither.
String? readRepoName(String vaultPath) {
  for (final f in localSyncFolders(vaultPath)) {
    try {
      final name = File('$vaultPath/$f/repo-name.txt').readAsStringSync().trim();
      if (name.isNotEmpty) return name;
    } catch (_) {}
  }
  return null;
}
