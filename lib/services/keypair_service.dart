// services/keypair_service.dart
//
// Generates the phone's own SSH keypair (ed25519, OpenSSH format) and
// writes it to the fixed location ssh_key_paths.dart defines. Part of the
// pairing feature - see lib/features/pairing/.

import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:openssh_ed25519/openssh_ed25519.dart';
import 'file_backup_exclusion.dart';
import 'ssh_key_paths.dart';

class KeypairService {
  /// Generates and writes the keypair if it doesn't already exist.
  /// Returns the public key line (e.g. "ssh-ed25519 AAAA... localsync").
  /// Idempotent - safe to call every time pairing starts.
  Future<String> ensureKeypair() async {
    final privatePath = await SshKeyPaths.privateKeyPath();
    final publicPath  = await SshKeyPaths.publicKeyPath();

    final privateFile = File(privatePath);
    final publicFile  = File(publicPath);

    if (await privateFile.exists() && await publicFile.exists()) {
      // 2026-08-28: real feedback, live - a device that already has a
      // keypair from BEFORE this fix existed (an in-place app upgrade,
      // not a fresh reinstall) would otherwise never get the exclusion
      // applied, since generation only happens once. Idempotent to call
      // again if it's already excluded, so this runs every time
      // regardless of which branch below is taken.
      await FileBackupExclusion.exclude(privatePath);
      await FileBackupExclusion.exclude(publicPath);
      return publicFile.readAsString();
    }

    final keyPair      = await Ed25519().newKeyPair();
    final privateBytes = await keyPair.extractPrivateKeyBytes();
    final publicKey    = await keyPair.extractPublicKey();
    final publicBytes  = publicKey.bytes;

    final publicLine = '${encodeEd25519Public(publicBytes)} localsync';
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

    return publicLine;
  }
}
