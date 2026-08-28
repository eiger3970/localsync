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

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dartssh2/dartssh2.dart';
import '../linking/linking_state.dart';
import '../../services/keypair_service.dart';

class PairingController extends ChangeNotifier {
  // 2026-08-28: real device bug, live - "same error" (desktopNotConfigured)
  // kept firing even after Settings was correctly saved. Root cause: this
  // controller is constructed once in linking_screen.dart's initState()
  // with a SNAPSHOT of LinkingController's desktopUser/desktopIp at that
  // moment - the normal flow is land on Stage 1 (both still empty) -> tap
  // the Settings reminder -> fill in -> come back to the SAME still-alive
  // LinkingScreen instance, whose initState never re-runs. These used to
  // be final, so the snapshot could never catch up. Mutable now, synced
  // fresh from LinkingController right before every pairing attempt (see
  // linking_screen.dart's own comment at the call site).
  String desktopUser;
  String desktopIp;
  final int sshPort;

  PairingController({
    required this.desktopUser,
    required this.desktopIp,
    this.sshPort = 22,
  });

  bool         _isRunning = false;
  StepResult?  _result;

  bool         get isRunning => _isRunning;
  StepResult?  get result    => _result;

  // 2026-08-28: real feedback, live - "normies need to be 100% informed"
  // before this app ever runs a privileged command with their password -
  // allowAutoInstallGit is the real, explicit choice from a new consent
  // screen (git_install_consent.dart), asked fresh on every pairing
  // attempt (2026-08-28 follow-up: no longer remembered - a security
  // consent, not a convenience prompt), never defaulted silently either
  // way.
  Future<void> pairWithPassword(String password,
      {required bool allowAutoInstallGit}) async {
    _isRunning = true;
    _result    = null;
    notifyListeners();

    // 2026-08-28: real device bug, live - main.dart's desktopUser/
    // desktopIp defaults are now blank (were this developer's own real
    // desktop info - see main.dart's own comment on why). A user who
    // taps PAIR NOW before ever visiting Settings used to hit
    // SSHSocket.connect('', ...), which throws a raw
    // "SocketException: Failed host lookup: """ that _diagnose() below
    // can't classify - shown as the generic "Something went wrong that
    // LocalSync did not expect." Caught here, before any connection is
    // even attempted, with a real, specific message instead.
    if (desktopUser.trim().isEmpty || desktopIp.trim().isEmpty) {
      _isRunning = false;
      // 2026-08-28: real feedback, live - "raw error not showing." This
      // guard fires before any real exception exists, so debugDetail
      // was left null on purpose - but with no diagnostic text at all,
      // it looked like the RAW ERROR section was broken/missing rather
      // than genuinely not applicable. Reports exactly which field(s)
      // are empty instead, since a user can otherwise be fooled into
      // thinking a value they typed was saved when Settings' own save
      // silently rejected it (see settings_screen.dart's _save() fix,
      // same session - a bad IP used to discard a valid username too).
      final missing = [
        if (desktopUser.trim().isEmpty) 'Desktop username',
        if (desktopIp.trim().isEmpty) 'IP address - desktop',
      ].join(', ');
      _result = StepFailure(LinkingError.desktopNotConfigured,
          debugDetail: 'Empty in Settings: $missing');
      notifyListeners();
      return;
    }

    try {
      final publicKeyLine = await KeypairService().ensureKeypair();

      // 2026-08-24: real feedback, live - a genuinely unreachable
      // desktop left "Pairing..." on screen for ~5 minutes before
      // finally showing the connection-failed message. No timeout was
      // passed here, so the wait was bounded only by the OS's own TCP
      // connect timeout, not by anything this app controls. 15s is
      // generous for a local-network connection (this only ever talks
      // to a device on the same LAN, never over the open internet) while
      // still failing fast enough to be usable.
      final socket = await _connectWithRetry();
      final client = SSHClient(
        socket,
        username: desktopUser,
        onPasswordRequest: () => password,
      );

      // Single-quoted, with any embedded single-quote escaped - the value
      // is our own generated public key line (fixed charset: base64 +
      // "ssh-ed25519 " prefix + " localsync" suffix), not attacker input,
      // but escaping costs nothing and avoids relying on that assumption.
      final escaped = publicKeyLine.replaceAll("'", r"'\''");
      // 2026-08-28: real feedback, live - "normies need computer with git
      // ... this needs a better setup." This is the one moment the app
      // ever has the desktop login password in memory (never stored,
      // discarded right after this call) - the only point a `sudo`
      // install can authenticate itself without a second prompt. Assumes
      // the login password is also the sudo password, true for the
      // single personal-desktop-account threat model this whole pairing
      // design already targets (see git_service.dart's cert-check
      // comment for the same stated assumption). Debian-based only -
      // macOS's real git install is Xcode Command Line Tools, an
      // interactive GUI license-accept dartssh2 can't drive headlessly,
      // so this leaves that path alone rather than half-automate it and
      // fail confusingly; unsupported-OS case still surfaces as a real,
      // diagnosable exit code instead of a silent no-op.
      final escapedPassword = password.replaceAll("'", r"'\''");
      // 2026-08-28, follow-up: allowAutoInstallGit false (the user chose
      // "I'll install it myself" on the consent screen) still checks for
      // git - just never attempts sudo either way. exit 4 is a new,
      // distinct code for "declined automatic install", separate from
      // exit 3's "can't automate on this OS at all" and exit 2's
      // "attempted and failed".
      final gitCheck = allowAutoInstallGit
          ? 'if ! command -v git >/dev/null 2>&1; then '
              '  if command -v apt-get >/dev/null 2>&1; then '
              "    echo '$escapedPassword' | sudo -S apt-get install -y git >/dev/null 2>&1 || exit 2; "
              '  else '
              '    exit 3; '
              '  fi; '
              'fi && '
          : 'command -v git >/dev/null 2>&1 || exit 4 && ';
      final command = '$gitCheck'
          'mkdir -p ~/.ssh && chmod 700 ~/.ssh && '
          "printf '%s\\n' '$escaped' >> ~/.ssh/authorized_keys && "
          'chmod 600 ~/.ssh/authorized_keys';

      final res = await client.runWithResult(command);
      client.close();

      if (res.exitCode == 4) {
        // 2026-08-28: chose "I'll install it myself" on the consent
        // screen, and git genuinely isn't there. Real command to run
        // manually, not a vague "install git" - apt-get is the one
        // package manager the consent screen's own dropdown already
        // named as supported.
        _result = const StepFailure(
          LinkingError.unclassifiedError,
          debugDetail: 'git is not installed on the desktop. Run this '
              'yourself in a terminal on the desktop, then try pairing '
              'again:\nsudo apt-get install -y git',
        );
      } else if (res.exitCode == 3) {
        // 2026-08-28: this desktop has no git and no apt-get (macOS,
        // most likely) - the auto-install path above deliberately
        // doesn't attempt anything there (see its own comment). Real,
        // specific guidance instead of the generic unclassifiedError
        // catch-all below.
        _result = const StepFailure(
          LinkingError.unclassifiedError,
          debugDetail: 'git is not installed and could not be installed '
              'automatically on this desktop. On macOS, install the Xcode '
              'Command Line Tools (run `git` once in Terminal and accept '
              'the prompt), then try pairing again.',
        );
      } else if (res.exitCode == 2) {
        _result = const StepFailure(
          LinkingError.unclassifiedError,
          debugDetail: 'Automatic git install failed on the desktop '
              '(sudo password rejected, or apt-get itself failed). '
              'Install git manually on the desktop, then try pairing again.',
        );
      } else if (res.exitCode != 0) {
        // 2026-08-23: real bug, found while investigating a separate
        // report - this reached connectionRefused for a command that
        // ran successfully (real TCP connect, real SSH auth, real
        // command execution) but returned a non-zero exit code -
        // nothing to do with the network being unreachable. Genuinely
        // unclassified (a permissions issue on the desktop's ~/.ssh,
        // a full disk, etc.) - unclassifiedError with the real stderr
        // attached is honest about that, rather than sending a user
        // chasing network troubleshooting for a shell command failure.
        _result = StepFailure(
          LinkingError.unclassifiedError,
          debugDetail: 'Remote command exited ${res.exitCode}: '
              '${String.fromCharCodes(res.stderr)}',
        );
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

  // 2026-08-26: real feedback, live - "SocketException: ... No route to
  // host ... The solution was I had to unnecessarily enter the password a
  // 2nd time." The correct password worked immediately on the next
  // attempt against the same IP - not a real, sustained unreachability,
  // just a route/ARP entry not ready yet right after a network change
  // (hotspot reconnect, app resume).
  //
  // 2026-08-26, follow-up: real feedback, live, again - a first fix here
  // used a single 800ms retry and the user still hit this. The user's
  // own manual "fix" (retype the password, tap submit again) necessarily
  // took several real seconds - noticing the error, typing, tapping -
  // not 800ms. Matching that actual timing instead of guessing short:
  // up to 3 attempts total, waiting 2s then 4s between them.
  Future<SSHSocket> _connectWithRetry() async {
    const delays = [Duration(seconds: 2), Duration(seconds: 4)];
    for (var attempt = 0; ; attempt++) {
      try {
        return await SSHSocket.connect(
          desktopIp,
          sshPort,
          timeout: const Duration(seconds: 15),
        );
      } on SocketException {
        if (attempt >= delays.length) rethrow;
        await Future.delayed(delays[attempt]);
      }
    }
  }

  // 2026-08-19: was defaulting anything unmatched to connectionRefused -
  // same misdiagnosis class fixed in git_service.dart's _diagnose() the
  // same day. See LinkingError.unclassifiedError.
  //
  // 2026-08-24: real bug, live - a deliberately wrong (but matching)
  // password showed "Cannot reach your desktop on the network" instead
  // of the correct "retype your password" message. Root cause traced
  // into dartssh2's own source (ssh_client.dart): a server that closes
  // the connection immediately after one failed password attempt
  // (common real-world SSH behavior, not a misconfiguration) throws
  // SSHAuthAbortError('Connection closed before authentication', ...)
  // - a message this function never checked for at all. It also
  // wouldn't have matched the old 'Authentication' check even if it
  // had, since that word appears lowercase there ("before
  // authentication"), not capitalized. Auth-related checks now run
  // first (a "connection closed" message is still fundamentally an
  // auth problem, not a network-reachability one) and match
  // case-insensitively.
  LinkingError _diagnose(Object e) {
    final msg = e.toString();
    final lower = msg.toLowerCase();
    if (msg.contains('SSHAuthFailError') ||
        msg.contains('SSHAuthAbortError') ||
        lower.contains('authentication') ||
        lower.contains('password')) {
      return LinkingError.pairingPasswordRejected;
    }
    if (msg.contains('Connection refused') ||
        msg.contains('No route to host') ||
        msg.contains('timed out')) {
      return LinkingError.connectionRefused;
    }
    return LinkingError.unclassifiedError;
  }
}
