// features/linking/linking_state.dart
//
// The phone-side linking sequence for Fresh Setup.
// Desktop vault already exists. Phone gets a copy.
//
// Exact steps from SSOT (Fresh Setup, steps 11–15):
//   11. Create Obsidian vault on phone → force close app
//   12. Clone bare repo in Working Copy via SSH URL
//   13. Link Working Copy repo → On My iPhone/Obsidian/Obsidian_phone_vault
//   14. Pull desktop data to phone
//   15. Verify identity → commit → push test
//
// Non-commutative. Any deviation requires full reset to idle.

enum LinkingStep {
  idle,

  /// Step 11a: Open Obsidian — user creates vault named Obsidian_phone_vault.
  obsidianCreateVault,

  /// Step 11b: PARKED — user must force-close Obsidian after vault created.
  awaitingObsidianForceClose,

  /// Step 12: Clone bare repo in Working Copy via SSH URL.
  workingCopyClone,

  /// Step 13a: Link Working Copy repo to On My iPhone/Obsidian/Obsidian_phone_vault.
  workingCopyLink,

  /// Step 13b: PARKED — link attempt fails (no index yet).
  /// User: force-close Obsidian → reopen → trust author → wait for indexing
  /// → force-close again → return here.
  awaitingObsidianIndex,

  /// Step 13c: Retry link after Obsidian has indexed.
  workingCopyLinkRetry,

  /// Step 13d: PARKED — link succeeds but Working Copy shows error banner.
  /// User must relaunch Working Copy to clear banner.
  awaitingWorkingCopyRelaunch,

  /// Step 14: Pull desktop data to phone.
  workingCopyPull,

  /// Step 15: Set identity, commit, push to verify sync works.
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
  };

  String get resolution => switch (this) {
    LinkingError.connectionRefused =>
      '1. Check your desktop is awake\n'
      '2. Connect phone to hotspot\n'
      '3. On desktop: sudo systemctl status ssh\n'
      '4. On desktop: ip addr show\n'
      '   Verify IP matches what is set in this app',
    LinkingError.sshAuthFailed =>
      '1. Working Copy → Settings → SSH Keys → Export Public Key\n'
      '2. Desktop: vi ~/.ssh/authorized_keys\n'
      '3. Paste the key, save (:wq)\n'
      '4. Desktop: chmod 600 ~/.ssh/authorized_keys',
    LinkingError.bareRepoNotFound =>
      'On desktop, verify the bare repo exists:\n'
      'ls ~/Documents/Git_bare_repo/Md_files_bare.git\n\n'
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
  };
}
