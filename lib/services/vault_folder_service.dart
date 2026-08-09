// services/vault_folder_service.dart
//
// Bridges to AppDelegate.swift's VaultFolderChannel (2026-08-09). See
// that file's comment for the full architecture reasoning: Obsidian
// creates and owns its vault folder itself; Synclocal has to request
// access to it afterward via iOS's real cross-app folder picker, the
// same mechanism Working Copy's "Link Repository to" uses under the
// hood - proven by the user's own years of real Working Copy usage
// documentation. A plain path string is not enough to retain access
// to another app's folder across launches - iOS requires a security-
// scoped bookmark, resolved and explicitly start/stop-accessed around
// every use.

import 'package:flutter/services.dart';

class VaultFolderResult {
  final String path;
  final String bookmark; // base64-encoded security-scoped bookmark
  const VaultFolderResult({required this.path, required this.bookmark});
}

class VaultFolderService {
  static const _channel = MethodChannel('synclocal/vault_folder');

  /// Presents the native folder picker so the user can select the
  /// Obsidian vault folder they already created (On My iPhone ->
  /// Obsidian -> <vault name>). Returns null if the user cancelled.
  Future<VaultFolderResult?> pickFolder() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('pickFolder');
    if (result == null) return null;
    return VaultFolderResult(
      path: result['path'] as String,
      bookmark: result['bookmark'] as String,
    );
  }

  /// Resolves a stored bookmark and begins access - must be paired with
  /// [stopAccessing] once the caller is done touching the folder.
  /// Returns the live, currently-accessible path, or null if the
  /// bookmark could not be resolved (folder moved/deleted/permission
  /// revoked - the user would need to pick it again via [pickFolder]).
  Future<String?> startAccessing(String bookmark) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'startAccessing',
        {'bookmark': bookmark},
      );
      return result?['path'] as String?;
    } on PlatformException {
      return null;
    }
  }

  /// Must be called after every [startAccessing] once the git operation
  /// using that folder has finished - iOS access is reference-counted
  /// per Apple's documented security-scoped resource pattern.
  Future<void> stopAccessing(String bookmark) async {
    await _channel.invokeMethod('stopAccessing', {'bookmark': bookmark});
  }
}
