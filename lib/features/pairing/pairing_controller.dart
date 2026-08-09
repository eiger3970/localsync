// features/pairing/pairing_controller.dart
//
// One-time-password pairing: connects to the desktop over SSH using the
// desktop login password (entered once, never stored), then appends the
// phone's own ed25519 public key to ~/.ssh/authorized_keys. Equivalent to
// ssh-copy-id. Chosen over a QR-code+pairing-token flow to avoid running
// any new network-facing service on the desktop - see lib/STRUCTURE.md.
//
// Reuses StepResult/StepFailure/LinkingError from the linking feature
// rather than inventing a separate result type, per this session's goal
// of keeping one extensible error vocabulary.

import 'package:flutter/foundation.dart';
import 'package:dartssh2/dartssh2.dart';
import '../linking/linking_state.dart';
import '../../services/keypair_service.dart';

class PairingController extends ChangeNotifier {
  final String desktopUser;
  final String desktopIp;
  final int    sshPort;

  PairingController({
    required this.desktopUser,
    required this.desktopIp,
    this.sshPort = 22,
  });

  bool         _isRunning = false;
  StepResult?  _result;

  bool         get isRunning => _isRunning;
  StepResult?  get result    => _result;

  Future<void> pairWithPassword(String password) async {
    _isRunning = true;
    _result    = null;
    notifyListeners();

    try {
      final publicKeyLine = await KeypairService().ensureKeypair();

      final socket = await SSHSocket.connect(desktopIp, sshPort);
      final client = SSHClient(
        socket,
        username: desktopUser,
        onPasswordRequest: () => password,
      );

      // Single-quoted, with any embedded single-quote escaped - the value
      // is our own generated public key line (fixed charset: base64 +
      // "ssh-ed25519 " prefix + " synclocal" suffix), not attacker input,
      // but escaping costs nothing and avoids relying on that assumption.
      final escaped = publicKeyLine.replaceAll("'", r"'\''");
      final command =
          'mkdir -p ~/.ssh && chmod 700 ~/.ssh && '
          "printf '%s\\n' '$escaped' >> ~/.ssh/authorized_keys && "
          'chmod 600 ~/.ssh/authorized_keys';

      final res = await client.runWithResult(command);
      client.close();

      if (res.exitCode != 0) {
        _result = const StepFailure(LinkingError.connectionRefused);
      } else {
        _result = const StepSuccess(message: 'Paired with desktop');
      }
    } catch (e) {
      _result = StepFailure(_diagnose(e), debugDetail: e.toString());
    } finally {
      _isRunning = false;
      notifyListeners();
    }
  }

  LinkingError _diagnose(Object e) {
    final msg = e.toString();
    if (msg.contains('Connection refused') ||
        msg.contains('No route to host') ||
        msg.contains('timed out'))            return LinkingError.connectionRefused;
    if (msg.contains('Authentication') ||
        msg.contains('SSHAuthFailError') ||
        msg.contains('password'))             return LinkingError.pairingPasswordRejected;
    return LinkingError.connectionRefused;
  }
}
