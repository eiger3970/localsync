// services/keypair_service.dart
//
// Generates the phone's own SSH keypair (ed25519, OpenSSH format) and
// writes it to the fixed location ssh_key_paths.dart defines. Part of the
// pairing feature - see lib/features/pairing/.

import 'dart:io';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:openssh_ed25519/openssh_ed25519.dart';
import 'file_backup_exclusion.dart';
import 'ssh_key_paths.dart';

// 2026-10-02: user - "What about other users who reinstall on their phones,
// can you have the app have good code that replaces keys rather than messing
// up people's phones?" His own desktop had 580 authorized_keys lines: every
// reinstall wiped Application Support, generated a NEW key and appended it.
// Two fixes here:
// 1. The keypair is also kept in the iOS Keychain (this device only, never
//    in backups - same stance as file_backup_exclusion.dart). Keychain items
//    survive deleting the app, so a reinstall restores the same key.
// 2. Every key carries a per-phone label ("localsync-<id>"), so pairing can
//    replace this phone's old line on the desktop instead of adding another.
class KeypairService {
  static const _store = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );
  static const _kPrivate = 'localsync_ssh_private';
  static const _kPublic = 'localsync_ssh_public';
  static const _kDevice = 'localsync_device_id';

  // Keychain only on Apple platforms; elsewhere (Linux preview build) the
  // files alone are the store, as before.
  static bool get _useKeychain => Platform.isIOS || Platform.isMacOS;

  static Future<String?> _read(String k) async {
    if (!_useKeychain) return null;
    try { return await _store.read(key: k); } catch (_) { return null; }
  }

  static Future<void> _write(String k, String v) async {
    if (!_useKeychain) return;
    try { await _store.write(key: k, value: v); } catch (_) { /* best-effort */ }
  }

  /// Stable label for this phone, e.g. "localsync-3f9a1c07". Kept in the
  /// Keychain so it survives reinstalls; pairing uses it to find and replace
  /// this phone's previous key on the desktop.
  static Future<String> deviceLabel() async {
    var id = await _read(_kDevice);
    if (id == null || id.isEmpty) {
      final r = Random.secure();
      id = List.generate(4, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await _write(_kDevice, id);
    }
    return 'localsync-$id';
  }

  // "ssh-ed25519 AAAA... <anything>" -> same key with this phone's label.
  static String _labelled(String line, String label) {
    final f = _oneLine(line).split(' ');
    return '${f[0]} ${f[1]} $label';
  }

  /// Generates and writes the keypair if it doesn't already exist.
  /// Returns the public key line (e.g. "ssh-ed25519 AAAA... localsync-3f9a1c07").
  /// Idempotent - safe to call every time pairing starts.
  Future<String> ensureKeypair() async {
    final privatePath = await SshKeyPaths.privateKeyPath();
    final publicPath  = await SshKeyPaths.publicKeyPath();

    final privateFile = File(privatePath);
    final publicFile  = File(publicPath);
    final label = await deviceLabel();

    // Reinstall: files are gone but the Keychain still has the key.
    if (!(await privateFile.exists() && await publicFile.exists())) {
      final kPriv = await _read(_kPrivate);
      final kPub = await _read(_kPublic);
      if (kPriv != null && kPub != null && kPriv.isNotEmpty && kPub.isNotEmpty) {
        await privateFile.create(recursive: true);
        await privateFile.writeAsString(kPriv);
        await publicFile.writeAsString(_oneLine(kPub));
        try { await Process.run('chmod', ['600', privatePath]); } catch (_) {}
      }
    }

    if (await privateFile.exists() && await publicFile.exists()) {
      // 2026-08-28: real feedback, live - a device that already has a
      // keypair from BEFORE this fix existed (an in-place app upgrade,
      // not a fresh reinstall) would otherwise never get the exclusion
      // applied, since generation only happens once. Idempotent to call
      // again if it's already excluded, so this runs every time
      // regardless of which branch below is taken.
      await FileBackupExclusion.exclude(privatePath);
      await FileBackupExclusion.exclude(publicPath);
      final existing = _oneLine(await publicFile.readAsString());
      // Phones that paired before the Keychain existed: copy the key in now,
      // so their next reinstall reuses it too.
      if (await _read(_kPrivate) == null) {
        await _write(_kPrivate, await privateFile.readAsString());
        await _write(_kPublic, existing);
      }
      return _labelled(existing, label);
    }

    final keyPair      = await Ed25519().newKeyPair();
    final privateBytes = await keyPair.extractPrivateKeyBytes();
    final publicKey    = await keyPair.extractPublicKey();
    final publicBytes  = publicKey.bytes;

    final publicLine = _oneLine('${encodeEd25519Public(publicBytes)} localsync');
    final privateText = encodeEd25519Private(
      privateBytes: privateBytes,
      publicBytes: publicBytes,
    );

    await privateFile.create(recursive: true);
    await privateFile.writeAsString(privateText);
    await publicFile.writeAsString(publicLine);

    // Private key should not be group/world readable, matching standard
    // SSH key file permissions (chmod 600). Best-effort - not every
    // platform's Dart io supports POSIX chmod bits the same way, but this
    // is the private Application Support dir either way, not the exposed
    // Documents folder, so this is defence in depth, not the only guard.
    try {
      await Process.run('chmod', ['600', privatePath]);
    } catch (_) {
      // Not fatal - e.g. not available on this platform.
    }

    // 2026-08-28: real feedback, live - close off private key material
    // ever being included in a device backup (see
    // file_backup_exclusion.dart's header for the full reasoning).
    // Best-effort, same as the chmod above.
    await FileBackupExclusion.exclude(privatePath);
    await FileBackupExclusion.exclude(publicPath);
    await _write(_kPrivate, privateText);
    await _write(_kPublic, publicLine);

    return _labelled(publicLine, label);
  }

  /// 2026-10-02: encodeEd25519Public() ends with '\n', so the
  /// " localsync" comment landed on its own line in the desktop's
  /// authorized_keys (2 lines per pairing). Collapse to one clean line;
  /// also repairs .pub files already written on phones that way.
  static String _oneLine(String line) =>
      line.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).join(' ');
}
