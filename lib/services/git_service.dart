import 'dart:io';
import '../features/linking/linking_state.dart';

/// Git operations via process invocation.
///
/// We shell out to `git` rather than using dart-git or libgit2 because:
/// - dart-git: push/pull unimplemented, unmaintained since 2022
/// - libgit2 via FFI: viable but App Store .dylib bundling is complex
/// - git via SSH process: battle-tested, full feature set, git is
///   available on iOS via a-shell or as a bundled binary
///
/// For MVP: use Working Copy's own git via URL scheme for on-device ops.
/// For desktop `synco` command: standard system git.
abstract class GitService {
  Future<StepResult> pullFromBareRepo();
  Future<StepResult> pushToBareRepo();
  Future<StepResult> getStatus();
  Future<bool> hasUncommittedChanges();
}

class GitServiceImpl implements GitService {
  final String bareRepoPath;    // Desktop: /home/rapi5/Documents/Git_bare_repo/Md_files_bare.git
  final String localVaultPath;  // Phone: On My iPhone/Obsidian/Obsidian_phone_vault
  final String sshHost;         // rapi5@172.20.10.6
  final int sshPort;

  GitServiceImpl({
    required this.bareRepoPath,
    required this.localVaultPath,
    required this.sshHost,
    this.sshPort = 22,
  });

  /// For MVP phase: delegate git pull to Working Copy via URL scheme.
  /// Working Copy handles the SSH auth and git protocol natively on iOS.
  ///
  /// Full implementation (Phase 2): use ssh process + git bundle
  /// or libgit2 FFI once App Store entitlements are confirmed.
  @override
  Future<StepResult> pullFromBareRepo() async {
    // Phase 1 MVP: Working Copy pull via URL scheme
    // working-copy://x-callback-url/pull?repo=REPO_NAME
    //
    // This is launched before the linking flow begins (precondition).
    // If Working Copy has already pulled recently, this is a no-op.

    // TODO(phase2): replace with direct SSH git pull
    // final result = await _runGit(['pull', 'origin', 'main']);

    return const StepSuccess(message: 'Pull delegated to Working Copy');
  }

  @override
  Future<StepResult> pushToBareRepo() async {
    // TODO(phase2): SSH git push
    return const StepSuccess(message: 'Push delegated to Working Copy');
  }

  @override
  Future<StepResult> getStatus() async {
    try {
      final result = await _runSshCommand('git -C $bareRepoPath log --oneline -1');
      if (result.exitCode != 0) {
        return StepFailure(
          error: LinkingError.bareRepoNotFound,
          diagnosis: result.stderr.toString(),
          resolution: LinkingError.bareRepoNotFound.resolution,
        );
      }
      return StepSuccess(message: result.stdout.toString().trim());
    } catch (e) {
      return StepFailure(
        error: LinkingError.sshConnectionFailed,
        diagnosis: e.toString(),
        resolution: LinkingError.sshConnectionFailed.resolution,
      );
    }
  }

  @override
  Future<bool> hasUncommittedChanges() async {
    // Phase 1: defer to Working Copy for on-device status
    return false;
  }

  // ─────────────────────────────────────────────
  // Internals
  // ─────────────────────────────────────────────

  Future<ProcessResult> _runSshCommand(String command) async {
    return Process.run('ssh', [
      '-p', sshPort.toString(),
      '-o', 'ConnectTimeout=5',
      '-o', 'StrictHostKeyChecking=no',
      sshHost,
      command,
    ]);
  }

  // Kept for Phase 2 direct git implementation
  // ignore: unused_element
  Future<ProcessResult> _runGit(List<String> args) async {
    return Process.run('git', ['-C', localVaultPath, ...args]);
  }
}
