// services/file_backup_exclusion.dart
//
// 2026-08-28: real feedback, live - a returning device backup/restore
// could silently reintroduce an old SSH keypair after the user deleted
// the app specifically to reset it (Application Support, where the
// keypair lives, is included in iCloud/iTunes device backups by
// default). Private key material shouldn't be backed up regardless of
// whether that's actually the cause of any one specific repro - this
// closes it off properly. Thin wrapper over AppDelegate.swift's
// FileUtilsChannel; best-effort by design, same "not fatal" contract
// keypair_service.dart's own chmod 600 already uses - a failure here
// (web, a platform without the channel, etc.) must never break key
// generation itself.

import 'package:flutter/services.dart';

class FileBackupExclusion {
  static const _channel = MethodChannel('localsync/file_utils');

  static Future<void> exclude(String path) async {
    try {
      await _channel.invokeMethod('excludeFromBackup', {'path': path});
    } catch (_) {
      // Not fatal - see header comment.
    }
  }
}
