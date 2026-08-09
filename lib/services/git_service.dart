import 'dart:io';
import 'package:git2dart/git2dart.dart';
import '../features/linking/linking_state.dart';

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
  final String bareRepoPath;      // Desktop: /home/rapi5/Documents/Git/pi5-obsidian/Git_bare_repo/Md_files_bare.git
  final String localVaultPath;    // Phone: Synclocal's own Documents dir (see Info.plist notes in STRUCTURE.md)
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

  Callbacks get _callbacks => Callbacks(credentials: _credentials);

  bool get _isCloned => Directory('$localVaultPath/.git').existsSync();

  @override
  Future<StepResult> pullFromBareRepo() async {
    try {
      if (!_isCloned) {
        Repository.clone(
          url: _remoteUrl,
          localPath: localVaultPath,
          callbacks: _callbacks,
        );
        return const StepSuccess(message: 'Cloned bare repo');
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
      return StepFailure(LinkingError.connectionRefused, debugDetail: e.toString());
    }
  }

  @override
  Future<StepResult> pushToBareRepo() async {
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
        return const StepSuccess(message: 'Pushed to bare repo');
      } finally {
        repo.free();
      }
    } catch (e) {
      // libgit2 surfaces a non-fast-forward push as a LibGit2Error, not a
      // distinct return value - can't currently tell that apart from other
      // push failures (auth, network) without inspecting the message.
      return StepFailure(LinkingError.cannotFastForward, debugDetail: e.toString());
    }
  }

  @override
  Future<StepResult> getStatus() async {
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
      return StepFailure(LinkingError.connectionRefused, debugDetail: e.toString());
    }
  }

  @override
  Future<bool> hasUncommittedChanges() async {
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
