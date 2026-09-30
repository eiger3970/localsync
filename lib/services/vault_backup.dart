// services/vault_backup.dart
//
// 2026-08-16: extracted from sync_service.dart's private
// _backupVaultIfNotEmpty/_copyDirectoryContents (added 2026-08-20 there,
// "make sure I don't lose data") after finding the same unprotected
// hard-reset-on-missing-.git pattern in git_service.dart's
// pullFromBareRepo() - the code path LinkingController actually uses for
// initial setup and for re-linking an existing vault folder (e.g. after
// a reinstall wipes the app's local git state and repo database, forcing
// the user back through vault picking with a folder that may already
// hold real, unsynced notes). That path's own comment assumed the
// target folder only ever contains "Obsidian's brand-new placeholder
// content" - true for a genuinely fresh vault, false for a re-link of an
// already-used one. sync_service.dart's own missing-.git recovery (a
// routine case there, not rare) already had this exact protection; this
// makes it available to both instead of only one.
//
// Plain top-level functions, no closures over instance state - safe to
// call from an isolate (sync_service.dart's pull runs in one) as well as
// the main isolate (git_service.dart's initial clone does not).

import 'dart:io';

import 'localsync_folder.dart';

String backupTimestamp() {
  final n = DateTime.now();
  String p2(int v) => v.toString().padLeft(2, '0');
  return '${n.year}${p2(n.month)}${p2(n.day)}${p2(n.hour)}${p2(n.minute)}';
}

// 2026-08-26: real feedback, live - "LocalSync Conflict Backups" and
// "LocalSync Vault Backup <timestamp>" used to each sit directly at the
// vault's top level, two separate items cluttering the same file list
// this app's own conflicts_screen.dart deliberately keeps things
// visible in (see its "How conflicts are kept safe" dialog). One
// dedicated top-level folder, not two, holding both kinds of backup as
// subfolders - see conflict_scanner.dart's matching use for "Conflict
// Backups". Deliberately NOT nested under a "Projects" folder or any
// other user-specific convention - the app can't assume a given vault
// is organized that way.
// 2026-09-24: this is now only the DEFAULT - a vault can move it (e.g.
// to Projects/LocalSync) via .localsync_folder, see localsync_folder.dart.
// Build paths with localSyncFolder(vaultPath), not this constant.
const kLocalSyncFolderName = 'LocalSync';

/// 2026-09-30: real incident - two full "Backup <date>" copies (made by two
/// phone links on 2026-09-29) sat in LocalSync/, synced to the desktop, and
/// both Obsidians indexed every note three times: desktop Obsidian at 100%
/// CPU, phone stuck on "Indexing vault". Full copies now go in this hidden
/// folder at the vault's top level:
///  - Obsidian never indexes a folder whose name starts with a dot;
///  - the sync never sends it (excludeFullBackupsFromSync), so each device
///    keeps its own copy and the other side never sees it;
///  - still inside the vault, the only folder the security-scoped bookmark
///    lets the app write to (see backupVaultIfNotEmpty), and it survives
///    deleting the app and iLoader reinstalls - the app's own storage
///    doesn't (sync_service.dart, "Fixed 2026-08-09").
/// Reached from LocalSync -> ⋮ -> Backups (the Files app hides dot folders).
const kFullBackupsFolder = '.localsync_backups';

/// A full-copy folder name: "Backup <date>", or "Vault Backup <date>"
/// from before 2026-09-25.
final _fullBackupName = RegExp(r'^(Vault )?Backup \d{12}$');

/// If [vaultPath] already has any content, copies the whole thing to a
/// timestamped folder before the caller does anything destructive to
/// it. Returns the backup's vault-relative path (e.g. "LocalSync/Vault
/// Backup 202609241415") if one was made, else null - 2026-09-24: was a
/// bool; the path is now shown to the user after setup ("tell them
/// WHERE their data was backed up").
///
/// 2026-08-18: was a *sibling* folder (`${vaultPath}_localsync_backup_
/// ...`, next to the vault, not inside it) - real device testing hit
/// `PathAccessException ... Operation not permitted` trying to create
/// it, reproducible on a fresh install (ruling out stale app state).
/// Root cause: a security-scoped bookmark only grants access within
/// the bookmarked folder itself, not to create new siblings in its
/// parent directory - the same reason "LocalSync Conflict Backups"
/// (created *inside* the vault) has never hit this, only this sibling
/// path did. Moved inside the vault to match.
Future<String?> backupVaultIfNotEmpty(String vaultPath) async {
  final dir = Directory(vaultPath);
  if (!await dir.exists()) return null;
  final entries = await dir.list().toList();
  if (entries.isEmpty) return null;

  // The backup folder now lives inside the very directory being copied
  // - skipName keeps this top-level call from walking straight into its
  // own just-created (empty) backup folder and copying it into itself.
  // Only applies at this top level; a genuine subdirectory deeper in
  // the tree that happens to share the name is never touched by it.
  // 2026-08-26: skips the whole kLocalSyncFolderName container now, not
  // just this one timestamped backup - a vault backup copying its own
  // sibling "Conflict Backups" folder into itself would be pointless
  // (see kLocalSyncFolderName's own doc for why they share one parent).
  // 2026-09-24: skips every LocalSync folder by full path, not one
  // top-level name - the folder can now be nested (e.g.
  // Projects/LocalSync, see localsync_folder.dart), and skipping the
  // whole "Projects" name would silently leave real notes out of the
  // backup.
  // 2026-09-25: user - free users sync plain folders; "Vault" is Obsidian
  // talk that confuses them. Plain "Backup <date>" for everyone.
  final backupName = 'Backup ${backupTimestamp()}';
  final skipPaths = {
    for (final f in localSyncFolders(vaultPath)) '$vaultPath/$f',
  };
  removeNestedGitCopies(vaultPath);
  excludeFullBackupsFromSync(vaultPath);
  await _copyDirectoryContents(
      dir, Directory('$vaultPath/$kFullBackupsFolder/$backupName'),
      skipPaths: skipPaths);
  return '$kFullBackupsFolder/$backupName';
}

/// Adds kFullBackupsFolder to the vault repo's own .git/info/exclude, so
/// staging never picks it up. Local to this device (info/exclude is never
/// synced), and leaves the user's own .gitignore alone. No .git yet (a
/// brand-new link backs up before Repository.init) - nothing to do; the
/// next staging call writes it. Never throws.
void excludeFullBackupsFromSync(String vaultPath) {
  try {
    if (!Directory('$vaultPath/.git').existsSync()) return;
    final file = File('$vaultPath/.git/info/exclude');
    const line = '/$kFullBackupsFolder/';
    final existing = file.existsSync() ? file.readAsStringSync() : '';
    if (existing.split('\n').any((l) => l.trim() == line)) return;
    file.parent.createSync(recursive: true);
    final sep = existing.isEmpty || existing.endsWith('\n') ? '' : '\n';
    file.writeAsStringSync('$existing$sep$line\n');
  } catch (_) {
    // Best-effort - staging also drops the folder from the index directly.
  }
}

/// Moves LocalSync's backups still sitting in a visible LocalSync folder
/// into kFullBackupsFolder - vaults backed up before 2026-09-30: full
/// copies ("Backup <date>", "Vault Backup <date>"), "Conflict Backups"
/// (merged file by file into the hidden one) and "Conflict Backups before
/// <date>". Moves inside the same vault, nothing deleted; the next sync
/// removes them from the other devices, where the desktop script moves its
/// own the same way. Returns how many folders were moved or merged.
int moveBackupsToHiddenFolder(String vaultPath) {
  var moved = 0;
  final destRoot = '$vaultPath/$kFullBackupsFolder';
  String freeName(String dir, String name) {
    var dest = '$dir/$name';
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    for (var n = 2; FileSystemEntity.typeSync(dest) != FileSystemEntityType.notFound; n++) {
      dest = '$dir/$stem ($n)$ext';
    }
    return dest;
  }

  for (final lsf in localSyncFolders(vaultPath)) {
    if (lsf == kFullBackupsFolder) continue;
    final dir = Directory('$vaultPath/$lsf');
    if (!dir.existsSync()) continue;
    for (final e in dir.listSync()) {
      if (e is! Directory) continue;
      final name = e.path.split('/').last;
      try {
        if (name == 'Conflict Backups') {
          final dest = Directory('$destRoot/Conflict Backups')
            ..createSync(recursive: true);
          for (final f in e.listSync()) {
            f.renameSync(freeName(dest.path, f.path.split('/').last));
          }
          e.deleteSync(); // empty now - non-recursive, fails if not
          moved++;
        } else if (_fullBackupName.hasMatch(name) ||
            name.startsWith('Conflict Backups before ')) {
          Directory(destRoot).createSync(recursive: true);
          e.renameSync(freeName(destRoot, name));
          moved++;
        }
      } catch (_) {
        // Left where it is - still a backup, just still visible.
      }
    }
  }
  return moved;
}

/// 2026-09-06: real feedback - "will they fill up a user's phone
/// storage?" Nothing pruned LocalSync/Conflict Backups before this, and
/// with auto-sync now running every time the app opens (see
/// AutoSyncOnResume), a backup can be written far more often than a
/// user will ever deliberately go looking in this folder. Best-effort,
/// one pass, meant to be called once per app session (from
/// AutoSyncOnResume) rather than after every single sync - deletes
/// anything older than [maxAge]. Parses the embedded timestamp already
/// in each filename (the same YYYYMMDDHHmm backupTimestamp() always
/// writes, right before the extension) instead of trusting file mtime,
/// which can shift unpredictably across a synced/copied file.
Future<void> pruneOldConflictBackups(String vaultPath,
    {Duration maxAge = const Duration(days: 30)}) async {
  // 2026-09-06: real device crash, same day - the exists() check used
  // to sit outside this function's own try/catch below, so any real
  // exception from it (a real one did fire on a real device, root
  // cause not yet pinned down - the call site in sync_service.dart's
  // _run() had no protection of its own either at the time) had
  // nothing catching it here. Whole function now wrapped, not just the
  // listing loop - "best-effort" needs to mean the entire thing, not
  // most of it.
  try {
    final dir = Directory(conflictBackupsDir(vaultPath));
    if (!await dir.exists()) return;
    final cutoff = DateTime.now().subtract(maxAge);
    final tsPattern = RegExp(r'(\d{12})(?:\.[^.]*)?$');
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final match = tsPattern.firstMatch(name);
      if (match == null) continue;
      final ts = match.group(1)!;
      final parsed = DateTime(
        int.parse(ts.substring(0, 4)),
        int.parse(ts.substring(4, 6)),
        int.parse(ts.substring(6, 8)),
        int.parse(ts.substring(8, 10)),
        int.parse(ts.substring(10, 12)),
      );
      if (parsed.isBefore(cutoff)) {
        try {
          await entity.delete();
        } catch (_) {
          // Best-effort - one file failing to delete shouldn't block
          // pruning the rest.
        }
      }
    }
  } catch (_) {
    // Best-effort safety net - never worth surfacing an error for.
  }
}

Future<void> _copyDirectoryContents(
  Directory source,
  Directory dest, {
  Set<String> skipPaths = const {},
}) async {
  await dest.create(recursive: true);
  await for (final entity in source.list(followLinks: false)) {
    final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    final entityPath = entity.path.endsWith('/')
        ? entity.path.substring(0, entity.path.length - 1)
        : entity.path;
    if (skipPaths.contains(entityPath)) continue;
    // 2026-09-29: real error, live, second setup on the same phone -
    // "GIT_ERROR_INDEX: invalid path: 'LocalSync/Backup 202609291652'".
    // The old vault still had its .git, the backup copied it, and git
    // refuses a repository nested inside the vault. Never copy .git.
    if (name == '.git') continue;
    final destPath = '${dest.path}/$name';
    if (entity is Directory) {
      await _copyDirectoryContents(entity, Directory(destPath),
          skipPaths: skipPaths);
    } else if (entity is File) {
      await entity.copy(destPath);
    }
  }
}

/// 2026-09-29: backups made before the .git skip above can hold a copied
/// .git folder (a repository nested inside the vault), which stops every
/// sync with GIT_ERROR_INDEX "invalid path". Removes any .git found inside
/// a LocalSync folder - they are only ever copies; the vault's own .git
/// sits at its root and is never touched.
void removeNestedGitCopies(String vaultPath) {
  for (final lsf in localSyncFolders(vaultPath)) {
    final dir = Directory('$vaultPath/$lsf');
    if (!dir.existsSync()) continue;
    for (final e in dir.listSync(recursive: true, followLinks: false)) {
      if (e is Directory && e.path.split('/').last == '.git' && e.existsSync()) {
        e.deleteSync(recursive: true);
      }
    }
  }
}
