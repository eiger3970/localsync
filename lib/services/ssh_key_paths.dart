// services/ssh_key_paths.dart
//
// Fixed on-device location for the phone's own SSH keypair, used to
// authenticate to the desktop bare repo. Actual key GENERATION is the
// pairing feature's job (WiFi hotspot + QR code SSH key exchange,
// lib/features/pairing/ - still unbuilt, see lib/STRUCTURE.md). This just
// defines where that feature will write the keys, so git_service.dart and
// sync_service.dart have a stable path to read from.
//
// Deliberately NOT under the app's Documents directory: that folder is
// exposed to the iOS Files app (UIFileSharingEnabled, see Info.plist) so
// the user can point Obsidian at it - a private key sitting there would be
// exportable via Files/Finder. Application Support stays private to the app.

import 'package:path_provider/path_provider.dart';

class SshKeyPaths {
  static Future<String> _supportDir() async =>
      (await getApplicationSupportDirectory()).path;

  static Future<String> privateKeyPath() async =>
      '${await _supportDir()}/synclocal_id_ed25519';

  static Future<String> publicKeyPath() async =>
      '${await _supportDir()}/synclocal_id_ed25519.pub';
}
