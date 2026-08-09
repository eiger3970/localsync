// features/linking/linking_state.dart
//
// The phone-side vault setup sequence. Desktop bare repo already exists.
// Phone clones it (via git2dart, in-process - see git_service.dart) into
// Synclocal's own Documents folder, then the user points Obsidian at that
// folder using its standard "Open folder as vault" picker. Rewritten
// 2026-08-08 - see lib/STRUCTURE.md for why this replaced the old
// Working Copy-driven multi-step link/retry sequence.

enum LinkingStep {
  idle,

  /// Precondition check: does the phone already have its own SSH keypair
  /// (from pairing - lib/features/pairing/, still unbuilt)? If not, fails
  /// clearly rather than attempting a clone that can't authenticate.
  checkingPairing,

  /// Real git2dart clone of the bare repo into Synclocal's own Documents
  /// directory. In-process - no external app, no parking. Replaces the old
  /// workingCopyClone + workingCopyLink + awaitingObsidianIndex +
  /// workingCopyLinkRetry + awaitingWorkingCopyRelaunch + workingCopyPull
  /// steps entirely: those existed to work around Working Copy's own
  /// "link" feature quirks, which no longer apply.
  cloning,

  /// PARKED — user opens Obsidian and uses its standard "Open folder as
  /// vault" to point at Files > On My iPhone > Synclocal (already
  /// populated by the clone above). This is the only remaining
  /// another-app step, and it's Obsidian's own normal onboarding flow,
  /// not a Working Copy-specific workaround.
  awaitingObsidianVaultOpen,

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
  const StepFailure(this.error);

  String get diagnosis  => error.diagnosis;
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

  /// Working Copy not installed.
  workingCopyNotInstalled,

  /// Obsidian not installed.
  obsidianNotInstalled,

  /// Vault directory already exists with data.
  vaultPathConflict,

  /// "Failed to resolve path /private/var/mobile/Containers/Shared/..."
  /// Occurs on 2nd+ link attempt — old path reference is stale.
  failedToResolvePath,

  /// "The index is locked — concurrent or crashed process."
  indexLocked,

  /// Working Copy shows "invalid argument 'repo'" after linking.
  /// Cosmetic only — link worked. Force close WC to clear.
  invalidArgumentRepo,

  /// Phone changes not appearing in Working Copy front page.
  commitNotShowing,

  /// "Unable to push — could not be fast-forwarded."
  cannotFastForward,

  /// Same line edited on both devices. Git cannot auto-resolve.
  mergeConflict,

  /// Git stuck mid-rebase. .git/rebase-merge lock exists.
  rebaseStuck,

  /// "Untracked files would be overwritten by merge."
  untrackedFilesOverwritten,

  /// Working Copy has no commit identity set.
  identityNotSet,

  /// Old vault files not fully removed — phone reboot needed.
  filesNotDeleting,

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
}

extension LinkingErrorDetails on LinkingError {
  String get diagnosis => switch (this) {
    LinkingError.connectionRefused =>
      'Cannot reach your desktop. SSH connection refused.',
    LinkingError.sshAuthFailed =>
      'SSH key rejected. Your phone key is not authorised on the desktop.',
    LinkingError.bareRepoNotFound =>
      'Bare repository not found at the configured path on your desktop.',
    LinkingError.workingCopyNotInstalled =>
      'Working Copy is not installed on this phone.',
    LinkingError.obsidianNotInstalled =>
      'Obsidian is not installed on this phone.',
    LinkingError.vaultPathConflict =>
      'A vault already exists at that path with data in it.',
    LinkingError.failedToResolvePath =>
      'Working Copy cannot find the vault path. The old path reference is stale.',
    LinkingError.indexLocked =>
      'Vault index is locked — a previous process crashed or is still running.',
    LinkingError.invalidArgumentRepo =>
      'Working Copy shows "invalid argument repo". This is cosmetic — the link worked.',
    LinkingError.commitNotShowing =>
      'Phone changes are not appearing in Working Copy. The app needs waking.',
    LinkingError.cannotFastForward =>
      'Cannot push — the remote has commits your phone does not have yet.',
    LinkingError.mergeConflict =>
      'The same line was edited on both devices. Git cannot auto-resolve.',
    LinkingError.rebaseStuck =>
      'Git is stuck mid-rebase. A lock file is blocking all git commands.',
    LinkingError.untrackedFilesOverwritten =>
      'A local file would be overwritten by the incoming pull.',
    LinkingError.identityNotSet =>
      'Working Copy has no commit identity. A name and email are required.',
    LinkingError.filesNotDeleting =>
      'Old vault files are not fully removed. A phone reboot is needed.',
    LinkingError.vaultNameEmpty =>
      'Vault name is empty.',
    LinkingError.unexpectedLinkError =>
      'Launching an external app failed unexpectedly.',
    LinkingError.pairingNotComplete =>
      'This phone has not been paired with your desktop yet.',
    LinkingError.pairingPasswordRejected =>
      'The desktop password entered was not accepted.',
  };

  String get resolution => switch (this) {
    LinkingError.connectionRefused =>
      '1. Check your desktop is awake\n'
      '2. Connect phone to hotspot\n'
      '3. On desktop: sudo systemctl status ssh\n'
      '4. On desktop: ip addr show\n'
      '   Verify IP matches what is set in this app',
    LinkingError.sshAuthFailed =>
      'Synclocal\'s own key was not accepted. During pairing this app\n'
      'shows a QR code containing its public key - scan it on the\n'
      'desktop to add it to ~/.ssh/authorized_keys automatically.\n'
      'If pairing was already completed, try it again.',
    LinkingError.bareRepoNotFound =>
      'On desktop, verify the bare repo exists:\n'
      'ls ~/Documents/Git/pi5-obsidian/Git_bare_repo/Md_files_bare.git\n\n'
      'If missing, run Fresh Setup steps 1–10 on your desktop first.',
    LinkingError.workingCopyNotInstalled =>
      'Install Working Copy from the App Store.\n'
      'Then restart setup.',
    LinkingError.obsidianNotInstalled =>
      'Install Obsidian from the App Store.\n'
      'Then restart setup.',
    LinkingError.vaultPathConflict =>
      '1. Delete Obsidian app (removes On My iPhone/Obsidian)\n'
      '2. Reboot phone — required to clear iOS file state\n'
      '3. Reinstall Obsidian\n'
      '4. Restart setup',
    LinkingError.failedToResolvePath =>
      '1. Force close Obsidian\n'
      '2. Reopen Obsidian — it will index files\n'
      '3. Tap "Trust author and enable plugins"\n'
      '4. Force close Obsidian again\n'
      '5. Return here and tap Continue',
    LinkingError.indexLocked =>
      '1. Open Obsidian\n'
      '2. Tap "Trust author and enable plugins"\n'
      '3. Working Copy and Obsidian will auto-sync',
    LinkingError.invalidArgumentRepo =>
      'Force close Working Copy completely, then reopen it.\n'
      'The banner will be gone. Everything worked correctly.',
    LinkingError.commitNotShowing =>
      'In Working Copy:\n'
      'Long press the repository → tap Pull\n'
      'This wakes the app and commits will appear.',
    LinkingError.cannotFastForward =>
      'In Working Copy:\n'
      'Tap the error → tap Merge → resolve → Commit → Push',
    LinkingError.mergeConflict =>
      'On desktop:\n'
      '1. git status\n'
      '2. Open conflicting file, remove <<<< ==== >>>> markers\n'
      '3. git add .\n'
      '4. git commit -m "Resolve conflict"\n'
      '5. git push origin master\n'
      'Then pull on phone in Working Copy.',
    LinkingError.rebaseStuck =>
      'On desktop:\n'
      'rm -f .git/index.lock\n'
      'rm -rf .git/rebase-merge\n'
      'git rebase --abort\n'
      'git checkout -f main\n'
      'git reset --hard origin/main',
    LinkingError.untrackedFilesOverwritten =>
      'On desktop:\n'
      'rm "path/to/conflicting/file.md"\n'
      'Then run synco again.',
    LinkingError.identityNotSet =>
      'In Working Copy, when prompted:\n'
      '1. Name: Git phone obsidian\n'
      '2. Email: phone@obsidian.local\n'
      '3. Tap tick\n'
      '4. Restart the commit',
    LinkingError.filesNotDeleting =>
      '1. Delete Obsidian app\n'
      '2. Delete Working Copy app\n'
      '3. Reboot phone — required\n'
      '4. Reinstall both apps\n'
      '5. Restart setup from the beginning',
    LinkingError.vaultNameEmpty =>
      'Set a vault name in Settings before running setup.',
    LinkingError.unexpectedLinkError =>
      'Check the target app is installed and try again.',
    LinkingError.pairingNotComplete =>
      'Run pairing first from Settings, then try setup again.',
    LinkingError.pairingPasswordRejected =>
      'Check the password and try again. This is your desktop login\n'
      'password, entered once just to install this phone\'s key - it\n'
      'is never stored.',
  };
}
