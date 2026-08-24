// features/linking/linking_state.dart
//
// The phone-side vault setup sequence. Desktop bare repo already exists.
//
// Rewritten 2026-08-09 with the flow direction corrected - real user
// documentation of years of working Working Copy usage revealed that
// Obsidian must create and own its vault folder first, and the sync
// tool requests access to it afterward via iOS's real cross-app folder
// picker (a security-scoped bookmark - see VaultFolderService and
// AppDelegate.swift's VaultFolderChannel). The previous 2026-08-08
// version had this backwards: cloning into Localsync's own private
// folder and expecting Obsidian to later "open" it - no such import
// path exists in Obsidian's iOS UI ("Open folder as vault" was never
// real). See lib/STRUCTURE.md for the full finding.

import '../../constants.dart';

enum LinkingStep {
  idle,

  /// Precondition check: does the phone already have its own SSH keypair
  /// (from pairing - lib/features/pairing/)? If not, fails clearly rather
  /// than attempting a clone that can't authenticate.
  checkingPairing,

  /// PARKED — user creates a brand new, empty vault directly in Obsidian
  /// ("Create a vault" -> "Continue without sync" -> name it -> "Create
  /// a vault"), on-device, not iCloud. This has to happen first: Obsidian
  /// is the only thing that can create a vault folder Obsidian will
  /// actually recognize.
  awaitingVaultCreation,

  /// User taps "Select vault folder" - presents iOS's native folder
  /// picker so Localsync can request access to the vault folder just
  /// created, obtaining a security-scoped bookmark.
  pickingVaultFolder,

  /// Real git2dart clone (technically init+fetch+reset, not a plain
  /// clone - the target folder is never empty, Obsidian already put a
  /// .obsidian/ dir there) of the bare repo into the picked vault
  /// folder. In-process, no parking.
  cloning,

  /// Confirm the vault folder has the expected content.
  verifySync,

  /// Terminal success.
  complete,

  /// Terminal failure — diagnosis and resolution attached.
  failed,
}

// ─────────────────────────────────────────────
// Step results
// ─────────────────────────────────────────────

sealed class StepResult {
  const StepResult();
}

class StepSuccess extends StepResult {
  final String? message;
  const StepSuccess({this.message});
}

class StepFailure extends StepResult {
  final LinkingError error;
  // Raw exception text, when available (2026-08-09: added after a real
  // pairing failure turned out to be misdiagnosed - sshd logs showed a
  // clean TCP connect immediately closed before any SSH protocol data,
  // pointing at a client-side dartssh2 failure, but the app's own
  // generic LinkingError message couldn't distinguish that from a
  // genuine unreachable-host case. Optional and purely diagnostic -
  // not shown unless present.
  final String? debugDetail;
  const StepFailure(this.error, {this.debugDetail});

  String get diagnosis => error.diagnosis;
  String get resolution => error.resolution;
}

// ─────────────────────────────────────────────
// Real errors — sourced directly from SSOT
// ─────────────────────────────────────────────

enum LinkingError {
  /// Working Copy can't reach desktop Pi via SSH.
  connectionRefused,

  /// SSH key not in desktop ~/.ssh/authorized_keys.
  sshAuthFailed,

  /// Bare repo path wrong or doesn't exist.
  bareRepoNotFound,

  /// Obsidian not installed.
  obsidianNotInstalled,

  /// Vault directory already exists with data.
  vaultPathConflict,

  /// "Failed to resolve path /private/var/mobile/Containers/Shared/..."
  /// Occurs on 2nd+ link attempt — old path reference is stale.
  failedToResolvePath,

  /// "The index is locked — concurrent or crashed process."
  indexLocked,

  /// "Unable to push — could not be fast-forwarded."
  cannotFastForward,

  /// Diverged history on first clone - real merge-conflict resolution
  /// deferred at initial-link time (git_service.dart's legacy
  /// pullFromBareRepo(), still used for the very first clone). Ordinary
  /// day-to-day pull/push conflicts never reach this - they're handled
  /// automatically by sync_service.dart's own conflict-repair pipeline
  /// (see the Conflicts screen) and never surface as a LinkingError at
  /// all. Narrow, but still real.
  mergeConflict,

  /// Vault name field left empty in Settings.
  vaultNameEmpty,

  /// Launching an external app's URL scheme threw an unexpected error.
  unexpectedLinkError,

  /// No SSH keypair found on-device yet - pairing (lib/features/pairing/,
  /// still unbuilt) hasn't run, so there's nothing to authenticate a clone
  /// with.
  pairingNotComplete,

  /// The one-time desktop password entered during pairing was rejected.
  /// Distinct from sshAuthFailed, which is about the phone's already-
  /// paired key being rejected later (different cause, different fix).
  pairingPasswordRejected,

  /// The cloned folder is missing or empty when reaching verifySync -
  /// added 2026-08-09 after _verifySync() was found to be a no-op that
  /// unconditionally reported success. This is the one thing Localsync
  /// can actually check from its own sandbox (whether the download
  /// produced real files) - it genuinely cannot see into Obsidian to
  /// confirm the folder was opened as a vault there, iOS doesn't allow
  /// one app to inspect another's state.
  cloneVerificationFailed,

  /// Could not resolve/re-access the security-scoped bookmark for the
  /// user's picked vault folder - added 2026-08-09 alongside the
  /// vault-folder-picker rework. Can happen if the folder was moved,
  /// renamed, or deleted after being picked, or if iOS revoked the
  /// bookmark for some other reason. Distinct from cloneVerificationFailed
  /// (that's about the download itself; this is about losing the
  /// permission to reach the folder at all).
  vaultFolderAccessLost,

  /// The native folder picker itself failed to open - added 2026-08-09
  /// after real-device testing found tapping SELECT VAULT FOLDER did
  /// nothing at all, silently. Distinct from vaultFolderAccessLost
  /// (that's a bookmark that stopped resolving after being picked
  /// successfully; this is the picker never launching in the first
  /// place).
  vaultPickerFailed,

  /// 2026-08-19: real device bug - both git_service.dart's and
  /// pairing_controller.dart's own _diagnose() only ever classified a
  /// handful of specific exception strings (credentials/auth,
  /// not-found) and silently defaulted everything else to
  /// connectionRefused - so a completely unrelated exception (a real
  /// case found on device: a filesystem PathAccessException from the
  /// vault-backup step) showed as "Cannot reach your desktop. SSH
  /// connection refused." and sent the user chasing network/pairing
  /// steps that had nothing to do with the real failure. This is the
  /// honest fallback for anything that doesn't match a known pattern -
  /// see the RAW ERROR section (StepFailure.debugDetail) for what
  /// actually happened.
  unclassifiedError,
}

extension LinkingErrorDetails on LinkingError {
  String get diagnosis => switch (this) {
        // 2026-08-23: real bug, live - "is this right, was SSH refused
        // because I didn't enter the correct password?" No - and the
        // wording itself was inaccurate, not just confusing. This one
        // label covers four different raw network conditions
        // (connection refused, no route to host, timed out, network
        // unreachable - see _diagnose() in git_service.dart), but only
        // literally means "refused" for one of them. "No route to
        // host" is the desktop being unreachable at all (wrong IP,
        // wrong network), not a rejected connection - a real, different
        // thing. Reworded to cover all four honestly instead of naming
        // the one specific condition that doesn't always apply.
        // 2026-08-24: real feedback, live - explicit direction to
        // reverse the 2026-08-23 removal below: on this user's real
        // desktop, a wrong password attempt surfaces here, not as
        // pairingPasswordRejected - the SSH server's behavior on a
        // failed auth attempt isn't uniform (some close the connection
        // in a way dartssh2 reports identically to a real network
        // failure, some don't), so this diagnosis can genuinely mean
        // either. Worded to cover both instead of asserting only one.
        LinkingError.connectionRefused =>
          'Cannot reach your desktop on the network, or your desktop is refusing the connection.',
        LinkingError.sshAuthFailed =>
          'SSH key rejected. Your phone key is not authorised on the desktop.',
        LinkingError.bareRepoNotFound =>
          'Git bare repo not found at the configured path on your desktop.',
        LinkingError.obsidianNotInstalled =>
          '$kNoteAppName is not installed on this phone.',
        LinkingError.vaultPathConflict =>
          'A vault already exists at that path with data in it.',
        // 2026-08-21: real feedback, live - "have you included all these
        // cases... some errors won't be applicable due to better
        // coding than Working Copy?" Cross-checking the user's own
        // research notes against this switch found this line still
        // said "Working Copy cannot find the vault path" - stale from
        // before the 2026-08-08/09 architecture pivot away from
        // Working Copy entirely. LocalSync itself resolves this path
        // now, not a third-party app.
        LinkingError.failedToResolvePath =>
          'LocalSync could not resolve the vault path. The old path reference is stale.',
        LinkingError.indexLocked =>
          'Vault index is locked - a previous process crashed or is still running.',
        LinkingError.cannotFastForward =>
          'Cannot push - the remote has commits your phone does not have yet.',
        LinkingError.mergeConflict =>
          'The vault folder you picked already has git history that conflicts with the desktop.',
        LinkingError.vaultNameEmpty => 'Vault name is empty.',
        LinkingError.unexpectedLinkError =>
          'Launching an external app failed unexpectedly.',
        LinkingError.pairingNotComplete =>
          'This phone has not been paired with your desktop yet.',
        LinkingError.pairingPasswordRejected =>
          'The desktop password entered was not accepted.',
        LinkingError.cloneVerificationFailed =>
          'Your notes were not found in the expected folder on this phone.',
        LinkingError.vaultFolderAccessLost =>
          'Localsync lost access to your vault folder.',
        LinkingError.vaultPickerFailed => 'Could not open Files.',
        LinkingError.unclassifiedError =>
          'Something went wrong that LocalSync did not expect.',
      };

  String get resolution => switch (this) {
        // 2026-08-21: real formatting bug, caught in a self-review
        // pass, not device feedback - the old 5-line version had a
        // trailing indented continuation line (no leading number) that
        // DiagCard's bulleted mode would render as its own top-level
        // "•" point, same visual weight as items 1-4, when it was
        // actually meant as a sub-note under item 4. Merged into item
        // 4 itself so the numbered list stays a clean 4 items.
        // 2026-08-23: real feedback, live - "Connect phone to hotspot"
        // assumed one specific connection type; user was on USB tether
        // at the time, where this line didn't apply. Reworded to cover
        // both, since the actual point is "phone and desktop reachable
        // on the same network," not which connection type that is.
        // Commands wrapped in backticks - DiagCard now renders those
        // in monospace so they read as commands, not prose (see its
        // own 2026-08-23 note).
        // 2026-08-23: "re-enter password" step added then removed same
        // day - a real device test that day showed a deliberately wrong
        // password surfacing as pairingPasswordRejected instead, so it
        // seemed to genuinely not apply here.
        // 2026-08-24: reversed on explicit, direct instruction - real
        // testing this time showed the exact opposite: a wrong password
        // landing on THIS error, not pairingPasswordRejected. SSH
        // servers don't all behave identically on a failed auth attempt
        // (see the diagnosis text above) - re-entering the password is
        // back as step 1, ahead of the pure network checks, since that's
        // what actually resolved it in practice.
        LinkingError.connectionRefused =>
          '1. Re-enter your desktop password - a mistyped password can '
              'surface as this error on some networks\n'
              '2. Check your desktop is awake\n'
              '3. Connect phone to desktop - hotspot or USB tether\n'
              '4. On desktop: `sudo systemctl status ssh`\n'
              '5. On desktop: `ip addr show` - verify IP matches what is set in this app',
        LinkingError.sshAuthFailed =>
          'Tap PAIR NOW below and enter your desktop login password once - '
              'this installs your phone\'s key in ~/.ssh/authorized_keys on the desktop.\n'
              'If you already paired, the key may not have reached the desktop '
              '(interrupted connection) - pairing again is safe to repeat.',
        LinkingError.bareRepoNotFound =>
          'On desktop, verify the bare repo exists at the path configured '
              'in main.dart\'s bareRepoPath (ls ~/Documents/Git/pi5-obsidian/'
              'Git_bare_repo/).\n\n'
              'If missing, run Fresh Setup steps 1–10 on your desktop first.',
        LinkingError.obsidianNotInstalled =>
          'Install $kNoteAppName from the App Store.\n'
              'Then restart setup.',
        LinkingError.vaultPathConflict =>
          '1. Delete $kNoteAppName app (removes On My iPhone/$kNoteAppName)\n'
              '2. Reboot phone - required to clear iOS file state\n'
              '3. Reinstall $kNoteAppName\n'
              '4. Restart setup',
        LinkingError.failedToResolvePath => '1. Force close $kNoteAppName\n'
            '2. Reopen $kNoteAppName - it will index files\n'
            '3. Tap "Trust author and enable plugins"\n'
            '4. Force close $kNoteAppName again\n'
            '5. Return here and tap Continue',
        // 2026-08-21: real feedback, live - three resolution strings
        // below still told the user to do something inside Working
        // Copy, an app LocalSync hasn't depended on since the
        // 2026-08-08/09 git2dart rewrite - dead advice for the app as
        // it actually exists today. Reworded to what genuinely
        // resolves each one in LocalSync's own UI.
        LinkingError.indexLocked =>
          'Tap TRY AGAIN - a fresh attempt usually clears a stale lock.\n'
              'If this keeps happening, force-quit and reopen LocalSync.',
        LinkingError.cannotFastForward =>
          'Tap PULL first - this downloads the newer commits and merges them in.\n'
              'Then push again.',
        LinkingError.mergeConflict =>
          'This can only happen when linking a vault folder that already has '
              'separate git history.\n'
              'Unlink this vault and pick a different, empty folder, or reset '
              'the desktop bare repo to one clean history first.',
        LinkingError.vaultNameEmpty =>
          'Set a vault name in Settings before running setup.',
        LinkingError.unexpectedLinkError =>
          'Check the target app is installed and try again.',
        LinkingError.pairingNotComplete =>
          'Drag the key into the lock below to pair, then try setup again.',
        LinkingError.pairingPasswordRejected =>
          // 2026-08-16: "it's impossible to check the password as it no
          // longer shows" - the field shreds itself on submit (never
          // stored, by design), so "check the password" told the user to
          // do something the app itself made impossible. The only real
          // available action is retyping it.
          'Retype your desktop password and try again.\n'
              'This is your desktop login password - used once, never stored.',
        LinkingError.cloneVerificationFailed =>
          'The download may not have finished, or the folder was moved or deleted after setup.\n'
              'Tap TRY AGAIN to re-download your notes.\n'
              'Nothing on your desktop is affected either way.',
        // 2026-08-19: "This should read as text that wraps with only
        // new lines for new sentences" - the manual \n breaks below
        // used to land at a fixed column width (formatted for a code
        // editor, not this app's actual proportional-font, variable-
        // width Text widget), so real device rendering split mid-
        // sentence instead of wrapping naturally. One \n per sentence
        // now; word-wrap within each sentence is left to the widget.
        // Same fix applied to every other prose (non-numbered-list)
        // resolution string in this switch, once this one exposed the
        // pattern - the numbered-step entries above are genuine lists
        // (each \n is a real distinct step) and are unaffected.
        LinkingError.vaultFolderAccessLost =>
          'This can happen if the folder was moved, renamed, or deleted after you picked it.\n'
              'Tap TRY AGAIN and tap the vault folder again.\n'
              'Nothing on your desktop or in the folder itself is affected.',
        LinkingError.vaultPickerFailed =>
          'Tap TRY AGAIN.\n'
              'If this keeps happening, force-closing and reopening Localsync may help.',
        LinkingError.unclassifiedError =>
          'Check the RAW ERROR section below for what actually happened.\n'
              'Tap TRY AGAIN - most causes here are one-off, not a real network or pairing problem.',
      };
}
