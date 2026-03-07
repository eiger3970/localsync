// services/sync_service.dart
//
// Dart port of live synco script (202603021301).
// SyncPhase lives in models/repository.dart — not duplicated here.

import 'dart:io';
import '../features/linking/linking_state.dart';
import '../models/repository.dart';

// ── Result types ───────────────────────────────────────────────────────────────

sealed class SyncResult { const SyncResult(); }

class SyncOk extends SyncResult {
  final String message;
  const SyncOk(this.message);
}

class SyncNoChanges extends SyncResult {
  const SyncNoChanges();
}

class SyncConflict extends SyncResult {
  final String conflictingFiles;
  const SyncConflict(this.conflictingFiles);
}

class SyncFailed extends SyncResult {
  final LinkingError error;
  const SyncFailed(this.error);
  String get diagnosis  => error.diagnosis;
  String get resolution => error.resolution;
}

// ── Sync events ────────────────────────────────────────────────────────────────

class SyncEvent {
  final SyncPhase?  phase;
  final SyncResult? result;
  const SyncEvent({this.phase, this.result});
  factory SyncEvent.phase(SyncPhase p)  => SyncEvent(phase: p);
  factory SyncEvent.done(SyncResult r)  => SyncEvent(result: r);
}

// ── SyncService ────────────────────────────────────────────────────────────────

class SyncService {
  final String vaultPath;  // absolute path to vault on desktop
  final String remoteUser;
  final String remoteHost;
  final int    remotePort;
  final String branch;

  SyncService({
    required this.vaultPath,
    required this.remoteUser,
    required this.remoteHost,
    this.remotePort = 22,
    this.branch     = 'main',
  });

  factory SyncService.fromRepo(Repository repo) => SyncService(
    vaultPath:  repo.obsidianVaultPath,
    remoteUser: repo.remoteUser,
    remoteHost: repo.remoteHost,
    remotePort: repo.remotePort,
    branch:     'main',
  );

  // ── Full sync — exact port of synco 202603021301 ───────────────────────────

  Stream<SyncEvent> fullSync({String? commitMessage}) async* {
    // 1. Commit any unsaved local changes
    yield SyncEvent.phase(SyncPhase.detecting);
    final hasChanges = await _hasUncommittedChanges();

    if (hasChanges) {
      yield SyncEvent.phase(SyncPhase.committing);
      final addResult = await _runGit(['add', '.']);
      if (addResult.exitCode != 0) {
        yield SyncEvent.done(SyncFailed(_diagnose(addResult.stderr.toString())));
        return;
      }
      final msg = commitMessage ?? 'synclocal ${_timestamp()}';
      final commitResult = await _runGit(['commit', '-m', msg]);
      if (commitResult.exitCode != 0 &&
          !commitResult.stdout.toString().contains('nothing to commit')) {
        yield SyncEvent.done(SyncFailed(_diagnose(commitResult.stderr.toString())));
        return;
      }
    }

    // 2. Fetch bare repo state — read-only
    yield SyncEvent.phase(SyncPhase.fetching);
    final fetchResult = await _runGit(['fetch', 'origin']);
    if (fetchResult.exitCode != 0) {
      yield SyncEvent.done(SyncFailed(_diagnose(fetchResult.stderr.toString())));
      return;
    }

    // 3. Compare LOCAL / REMOTE / BASE
    final local  = await _revParse('HEAD');
    final remote = await _revParse('origin/$branch');
    final base   = await _mergeBase('HEAD', 'origin/$branch');

    if (local == null || remote == null || base == null) {
      yield SyncEvent.done(const SyncFailed(LinkingError.bareRepoNotFound));
      return;
    }

    if (local == remote) {
      yield SyncEvent.done(const SyncNoChanges());
      return;
    }

    if (local == base) {
      // Bare repo ahead — pull down
      yield SyncEvent.phase(SyncPhase.pulling);
      final r = await _runGit(['merge', '--ff-only', 'origin/$branch']);
      if (r.exitCode != 0) {
        yield SyncEvent.done(SyncFailed(_diagnose(r.stderr.toString())));
        return;
      }
      yield SyncEvent.done(SyncOk('Downloaded latest notes'));
      return;
    }

    if (remote == base) {
      // Desktop ahead — push up
      yield SyncEvent.phase(SyncPhase.pushing);
      final r = await _runGit(['push', 'origin', branch]);
      if (r.exitCode != 0) {
        yield SyncEvent.done(SyncFailed(_diagnose(r.stderr.toString())));
        return;
      }
      yield SyncEvent.done(SyncOk('Uploaded notes to desktop'));
      return;
    }

    // Diverged — merge required
    yield SyncEvent.phase(SyncPhase.merging);
    final mergeResult = await _runGit([
      'merge', '--no-ff', '-m',
      'Merge desktop and phone ${_timestamp()}',
      'origin/$branch',
    ]);

    if (mergeResult.exitCode == 0) {
      final pushResult = await _runGit(['push', 'origin', branch]);
      if (pushResult.exitCode != 0) {
        yield SyncEvent.done(SyncFailed(_diagnose(pushResult.stderr.toString())));
        return;
      }
      yield SyncEvent.done(SyncOk('Merged and synced'));
      return;
    }

    final statusResult = await _runGit(['diff', '--name-only', '--diff-filter=U']);
    await _runGit(['merge', '--abort']);
    yield SyncEvent.done(SyncConflict(statusResult.stdout.toString().trim()));
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  Future<bool> _hasUncommittedChanges() async {
    final r = await _runGit(['status', '--porcelain']);
    return r.exitCode == 0 && r.stdout.toString().trim().isNotEmpty;
  }

  Future<String?> _revParse(String ref) async {
    final r = await _runGit(['rev-parse', ref]);
    if (r.exitCode != 0) return null;
    return r.stdout.toString().trim();
  }

  Future<String?> _mergeBase(String a, String b) async {
    final r = await _runGit(['merge-base', a, b]);
    if (r.exitCode != 0) return null;
    return r.stdout.toString().trim();
  }

  Future<ProcessResult> _runGit(List<String> args) => Process.run(
    'git',
    ['-C', vaultPath, ...args],
    environment: {
      'GIT_SSH_COMMAND':
        'ssh -p $remotePort -o StrictHostKeyChecking=no -o ConnectTimeout=5',
    },
  );

  String _timestamp() {
    final n = DateTime.now();
    return '${n.year}-${_p(n.month)}-${_p(n.day)} '
           '${_p(n.hour)}:${_p(n.minute)}:${_p(n.second)}';
  }

  String _p(int n) => n.toString().padLeft(2, '0');

  LinkingError _diagnose(String stderr) {
    if (stderr.contains('Connection refused') ||
        stderr.contains('No route to host') ||
        stderr.contains('timed out')) return LinkingError.connectionRefused;
    if (stderr.contains('Permission denied') &&
        stderr.contains('publickey'))         return LinkingError.sshAuthFailed;
    if (stderr.contains('does not appear to be a git repository'))
                                              return LinkingError.bareRepoNotFound;
    if (stderr.contains('CONFLICT'))          return LinkingError.mergeConflict;
    if (stderr.contains('rebase-merge') ||
        stderr.contains('rebase in progress'))return LinkingError.rebaseStuck;
    if (stderr.contains('untracked working tree files'))
                                              return LinkingError.untrackedFilesOverwritten;
    if (stderr.contains('non-fast-forward') ||
        stderr.contains('could not be fast-forwarded'))
                                              return LinkingError.cannotFastForward;
    if (stderr.contains('index.lock'))        return LinkingError.indexLocked;
    return LinkingError.mergeConflict;
  }
}
