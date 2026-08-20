import 'dart:io';
import 'package:git2dart/git2dart.dart';
import '../features/linking/linking_state.dart';
import 'vault_backup.dart';

/// Git operations via git2dart (FFI bindings to libgit2, statically linked
/// on iOS via CocoaPods - see lib/STRUCTURE.md for why this replaced the
/// original Working Copy delegation plan).
///
/// Wired into linking_controller.dart's _clone() (pullFromBareRepo) since
/// the 2026-08-08 rewrite.
abstract class GitService {
  Future<StepResult> pullFromBareRepo();
  Future<StepResult> pushToBareRepo();
  Future<StepResult> getStatus();
  Future<bool> hasUncommittedChanges();
}

class GitServiceImpl implements GitService {
  // 2026-08-20: "opening app and a white screen took about 5 seconds,
  // can this be optimised" - PlatformSpecific.initialize() (git2dart's
  // own native libgit2 load, eager on iOS) used to run in main()
  // before runApp(), blocking even the very first Flutter frame -
  // nothing, not even the loading spinner, could render until it
  // finished. Moved here instead, lazily and memoized so it only ever
  // actually runs once, right before the first real git operation - by
  // which point the home screen (with its own "syncing..." status UI)
  // is already visible, so the latency is absorbed by UI the user
  // already sees as working instead of a blank white screen.
  static Future<void>? _platformInit;
  static Future<void> _ensurePlatformInitialized() =>
      _platformInit ??= PlatformSpecific.initialize();

  final String bareRepoPath;      // Desktop: whichever bare repo is configured in main.dart's LinkingController
  final String localVaultPath;    // Phone: Localsync's own Documents dir (see Info.plist notes in STRUCTURE.md)
  final String sshHost;           // Desktop's current hotspot-subnet IP, re-check each session (no settings UI yet)
  final int sshPort;
  final String sshUser;           // rapi5
  final String sshPrivateKeyPath; // On-device path to the phone's own SSH private key
  final String sshPublicKeyPath;  // On-device path to the phone's own SSH public key
  final String sshPassphrase;     // Empty string if the key has no passphrase

  /// Branch name on the bare repo. The codebase's own error-resolution text
  /// disagreed with itself (some strings said "main", one said "master") -
  /// making this a constructor param instead of hardcoding avoids guessing
  /// wrong. Confirm against the real bare repo once Fresh Setup steps 1-10
  /// have actually created it (it didn't exist yet as of 2026-08-08).
  final String defaultBranch;

  GitServiceImpl({
    required this.bareRepoPath,
    required this.localVaultPath,
    required this.sshHost,
    required this.sshUser,
    required this.sshPrivateKeyPath,
    required this.sshPublicKeyPath,
    this.sshPort = 22,
    this.defaultBranch = 'main',
    this.sshPassphrase = '',
  });

  String get _remoteUrl => 'ssh://$sshUser@$sshHost:$sshPort$bareRepoPath';

  Credentials get _credentials => Keypair(
        username: sshUser,
        pubKey: sshPublicKeyPath,
        privateKey: sshPrivateKeyPath,
        passPhrase: sshPassphrase,
      );

  // certificateCheck: without this, libgit2 falls back to its default
  // strict SSH host-key check against a known_hosts file - which doesn't
  // exist on iOS (git2dart's own docs flag this exact gap, "especially
  // useful on platforms such as Android where SSH known_hosts lookup may
  // not be available"). Every connection failed with GIT_ERROR_SSH
  // "invalid or unknown remote ssh hostkey" until this was added.
  // Accepting unconditionally is acceptable for this app's actual threat
  // model: a single personal desktop reached over a private USB/WiFi
  // hotspot link, not routed over the open internet, with trust already
  // established via the password-based pairing step (features/pairing/) -
  // not a general-purpose SSH client connecting to arbitrary hosts.
  Callbacks get _callbacks => Callbacks(
        credentials: _credentials,
        certificateCheck: (certificate, host, {required valid}) => true,
      );

  /// Classifies a caught exception into the right LinkingError instead of
  /// defaulting everything to connectionRefused - a real credentials
  /// failure ("Incorrect credentials") was showing the wrong diagnosis
  /// and a dead-end "check your network" resolution with no PAIR NOW
  /// button, confirmed 2026-08-09 from the debugDetail text on a real
  /// device. Mirrors pairing_controller.dart's _diagnose().
  ///
  /// 2026-08-19: the fallback below used to default anything unmatched
  /// to connectionRefused too - same bug, just not fully fixed the
  /// first time. Confirmed on real device: a PathAccessException from
  /// vault_backup.dart's EPERM (nothing to do with the network) showed
  /// as "Cannot reach your desktop. SSH connection refused." and sent
  /// the user chasing pairing/network steps for a filesystem bug. See
  /// LinkingError.unclassifiedError.
  LinkingError _diagnose(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('credential') ||
        msg.contains('auth') ||
        msg.contains('permission denied') ||
        msg.contains('hostkey') ||
        msg.contains('host key')) {
      return LinkingError.sshAuthFailed;
    }
    if (msg.contains('not found') || msg.contains('no such file')) {
      return LinkingError.bareRepoNotFound;
    }
    if (msg.contains('connection refused') ||
        msg.contains('no route to host') ||
        msg.contains('timed out') ||
        msg.contains('network is unreachable')) {
      return LinkingError.connectionRefused;
    }
    return LinkingError.unclassifiedError;
  }

  bool get _isCloned => Directory('$localVaultPath/.git').existsSync();

  @override
  Future<StepResult> pullFromBareRepo() async {
    await _ensurePlatformInitialized();
    try {
      if (!_isCloned) {
        // Was Repository.clone() until 2026-08-09 - required an empty
        // target directory, but localVaultPath is now the user's own
        // Obsidian vault folder (created via Obsidian's own "Create a
        // vault" flow, per the corrected architecture in STRUCTURE.md -
        // real user documentation of years of working Working Copy
        // usage showed Obsidian must create/own the vault folder
        // first). That folder already has a .obsidian/ config dir and
        // possibly a welcome note from Obsidian's own vault creation -
        // a plain clone would reject the non-empty directory. Instead:
        // init a repo in place, fetch, then hard-reset onto the fetched
        // branch - the same thing real `git init && git remote add &&
        // git fetch && git reset --hard origin/main` does on a fresh
        // non-empty directory, and libgit2's hard reset force-
        // overwrites conflicting untracked files during its checkout
        // step.
        //
        // 2026-08-16: that last sentence's framing - "Obsidian's
        // brand-new placeholder content is safely replaced" - only
        // holds for a genuinely fresh vault. This exact !_isCloned
        // branch is also what runs when re-linking an *already-used*
        // vault folder (e.g. after a reinstall wipes the app's local
        // git state and repo database, forcing the user back through
        // vault picking against a folder that may hold real, unsynced
        // notes) - the hard reset below would force-overwrite those
        // with zero warning. sync_service.dart's own missing-.git
        // recovery already backs up first for exactly this reason
        // ("make sure I don't lose data", 2026-08-20) - this path
        // handles the same missing-.git condition and needs the same
        // protection, not a narrower one.
        final backedUp = await backupVaultIfNotEmpty(localVaultPath);
        final repo = Repository.init(
          path: localVaultPath,
          initialHead: defaultBranch,
          originUrl: _remoteUrl,
        );
        try {
          final remote = Remote.lookup(repo: repo, name: 'origin');
          remote.fetch(callbacks: _callbacks);
          final remoteBranch = Branch.lookup(
            repo: repo,
            name: 'origin/$defaultBranch',
            type: GitBranch.remote,
          );
          repo.reset(oid: remoteBranch.target, resetType: GitReset.hard);
        } finally {
          repo.free();
        }
        return StepSuccess(
            message: backedUp
                ? 'Cloned bare repo (existing folder content backed up first).'
                : 'Cloned bare repo');
      }

      final repo = Repository.open(localVaultPath);
      try {
        final remote = Remote.lookup(repo: repo, name: 'origin');
        remote.fetch(callbacks: _callbacks);

        final remoteBranch = Branch.lookup(
          repo: repo,
          name: 'origin/$defaultBranch',
          type: GitBranch.remote,
        );
        final analysis = Merge.analysis(
          repo: repo,
          theirHead: remoteBranch.target,
        );

        if (analysis.result.contains(GitMergeAnalysis.upToDate)) {
          return const StepSuccess(message: 'Already up to date');
        }
        if (analysis.result.contains(GitMergeAnalysis.fastForward)) {
          repo.reset(oid: remoteBranch.target, resetType: GitReset.hard);
          return const StepSuccess(message: 'Pulled (fast-forward)');
        }

        // Diverged history - real merge-conflict resolution deferred per
        // 2026-08-08 scope decision (minimal happy-path now, hard recovery
        // cases later). Surfacing this as a clear failure rather than
        // attempting an automatic merge.
        return const StepFailure(LinkingError.mergeConflict);
      } finally {
        repo.free();
      }
    } catch (e) {
      return StepFailure(_diagnose(e), debugDetail: e.toString());
    }
  }

  @override
  Future<StepResult> pushToBareRepo() async {
    await _ensurePlatformInitialized();
    if (!_isCloned) {
      return const StepFailure(LinkingError.bareRepoNotFound);
    }
    try {
      final repo = Repository.open(localVaultPath);
      try {
        final remote = Remote.lookup(repo: repo, name: 'origin');
        remote.push(
          refspecs: ['refs/heads/$defaultBranch:refs/heads/$defaultBranch'],
          callbacks: _callbacks,
        );
        return const StepSuccess(message: 'Pushed to bare repo.');
      } finally {
        repo.free();
      }
    } catch (e) {
      // libgit2 surfaces a non-fast-forward push as a LibGit2Error, not a
      // distinct return value - _diagnose() catches the auth/credentials
      // case first now; cannotFastForward remains the fallback for
      // anything else, which is the actual common case for a push
      // specifically (rejected because the remote moved ahead).
      final diagnosed = _diagnose(e);
      final error = diagnosed == LinkingError.connectionRefused
          ? LinkingError.cannotFastForward
          : diagnosed;
      return StepFailure(error, debugDetail: e.toString());
    }
  }

  @override
  Future<StepResult> getStatus() async {
    await _ensurePlatformInitialized();
    if (!_isCloned) {
      return const StepFailure(LinkingError.bareRepoNotFound);
    }
    try {
      final repo = Repository.open(localVaultPath);
      try {
        final remote = Remote.lookup(repo: repo, name: 'origin');
        final refs = remote.ls(callbacks: _callbacks);
        final head = refs.firstWhere(
          (r) => r.name == 'refs/heads/$defaultBranch',
          orElse: () => refs.first,
        );
        return StepSuccess(message: head.oid.sha.substring(0, 7));
      } finally {
        repo.free();
      }
    } catch (e) {
      return StepFailure(_diagnose(e), debugDetail: e.toString());
    }
  }

  @override
  Future<bool> hasUncommittedChanges() async {
    await _ensurePlatformInitialized();
    if (!_isCloned) return false;
    try {
      final repo = Repository.open(localVaultPath);
      try {
        return repo.status.isNotEmpty;
      } finally {
        repo.free();
      }
    } catch (_) {
      return false;
    }
  }
}
