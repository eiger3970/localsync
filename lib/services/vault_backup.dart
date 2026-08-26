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
const kLocalSyncFolderName = 'LocalSync';

/// If [vaultPath] already has any content, copies the whole thing to a
/// timestamped folder before the caller does anything destructive to
/// it. Returns true if a backup was actually made.
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
Future<bool> backupVaultIfNotEmpty(String vaultPath) async {
  final dir = Directory(vaultPath);
  if (!await dir.exists()) return false;
  final entries = await dir.list().toList();
  if (entries.isEmpty) return false;

  // The backup folder now lives inside the very directory being copied
  // - skipName keeps this top-level call from walking straight into its
  // own just-created (empty) backup folder and copying it into itself.
  // Only applies at this top level; a genuine subdirectory deeper in
  // the tree that happens to share the name is never touched by it.
  // 2026-08-26: skips the whole kLocalSyncFolderName container now, not
  // just this one timestamped backup - a vault backup copying its own
  // sibling "Conflict Backups" folder into itself would be pointless
  // (see kLocalSyncFolderName's own doc for why they share one parent).
  final backupName = 'Vault Backup ${backupTimestamp()}';
  await _copyDirectoryContents(
      dir, Directory('$vaultPath/$kLocalSyncFolderName/$backupName'),
      skipName: kLocalSyncFolderName);
  return true;
}

Future<void> _copyDirectoryContents(
  Directory source,
  Directory dest, {
  String? skipName,
}) async {
  await dest.create(recursive: true);
  await for (final entity in source.list(followLinks: false)) {
    final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    if (name == skipName) continue;
    final destPath = '${dest.path}/$name';
    if (entity is Directory) {
      await _copyDirectoryContents(entity, Directory(destPath));
    } else if (entity is File) {
      await entity.copy(destPath);
    }
  }
}
