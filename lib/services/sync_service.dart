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
  final String vaultPath;
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

  // ── Full sync ──────────────────────────────────────────────────────────────

  Stream<SyncEvent> fullSync({String? commitMessage}) async* {
    // Guard: Process.run is not supported on iOS
    if (!Platform.isLinux && !Platform.isMacOS && !Platform.isWindows) {
      yield SyncEvent.done(const SyncFailed(LinkingError.connectionRefused));
      return;
    }

    // 1. Recover from any stuck merge from a previous crashed run
    if (await _fileExists('$vaultPath/.git/MERGE_HEAD')) {
      await _repairAllConflicts();
      if (await _fileExists('$vaultPath/.git/MERGE_HEAD')) {
        await _runGit(['commit', '--no-edit']);
      }
    }

    // 2. Commit any unsaved local changes
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

    // 3. Fetch
    yield SyncEvent.phase(SyncPhase.fetching);
    final fetchResult = await _runGit(['fetch', 'origin']);
    if (fetchResult.exitCode != 0) {
      yield SyncEvent.done(SyncFailed(_diagnose(fetchResult.stderr.toString())));
      return;
    }

    // 4. Compare LOCAL / REMOTE / BASE
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
      yield SyncEvent.phase(SyncPhase.pushing);
      final r = await _pushWithRetry();
      if (r != null) {
        yield SyncEvent.done(SyncFailed(_diagnose(r)));
        return;
      }
      yield SyncEvent.done(SyncOk('Uploaded notes to desktop'));
      return;
    }

    // Diverged — three-way merge
    yield SyncEvent.phase(SyncPhase.merging);
    final mergeResult = await _runGit([
      'merge', '--no-ff', '-m',
      'Merge desktop and phone ${_timestamp()}',
      'origin/$branch',
    ]);

    if (mergeResult.exitCode != 0) {
      // Conflict: repair both sides instead of aborting
      await _repairAllConflicts();
      if (await _fileExists('$vaultPath/.git/MERGE_HEAD')) {
        // repair found nothing — tree was clean but merge not committed
        await _runGit(['commit', '--no-edit']);
      }
    }

    final pushErr = await _pushWithRetry();
    if (pushErr != null) {
      yield SyncEvent.done(SyncFailed(_diagnose(pushErr)));
      return;
    }
    yield SyncEvent.done(SyncOk('Merged and synced'));
  }

  // ── Conflict repair — mirrors repair_conflicts.py ──────────────────────────

  Future<void> _repairAllConflicts() async {
    final dir = Directory(vaultPath);
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.md')) continue;
      try {
        final content = await entity.readAsString();
        if (!content.contains('<<<<<<< ')) continue;
        final repaired = _repairConflictMarkers(content);
        await entity.writeAsString(repaired);
      } catch (_) {
        // Skip unreadable files
      }
    }
    await _runGit(['add', '.']);
    final r = await _runGit(['diff', '--cached', '--quiet']);
    if (r.exitCode != 0) {
      await _runGit([
        'commit', '-m',
        'Merge conflicts (both sides kept) ${_timestamp()}',
      ]);
    }
  }

  String _repairConflictMarkers(String content) {
    final pattern = RegExp(
      r'^<<<<<<< [^\n]*\n(.*?)\n=======\n(.*?)\n>>>>>>> [^\n]*\n?',
      multiLine: true,
      dotAll: true,
    );
    return content.replaceAllMapped(pattern, (m) {
      final ours   = m.group(1)!.trim();
      final theirs = m.group(2)!.trim();
      final callout = theirs.split('\n').map((l) => '> $l').join('\n');
      return '$ours\n\n'
             '> [!warning]+ SYNC CONFLICT — other device version (review and delete one)\n'
             '$callout\n\n';
    });
  }

  // ── Push with one retry on non-fast-forward rejection ─────────────────────

  Future<String?> _pushWithRetry() async {
    final r = await _runGit(['push', 'origin', branch]);
    if (r.exitCode == 0) return null;
    final stderr = r.stderr.toString();
    if (!stderr.contains('non-fast-forward') &&
        !stderr.contains('could not be fast-forwarded')) {
      return stderr;
    }
    // Remote moved — fetch and fast-forward, then retry
    await _runGit(['fetch', 'origin']);
    final ff = await _runGit(['merge', '--ff-only', 'origin/$branch']);
    if (ff.exitCode != 0) return ff.stderr.toString();
    final retry = await _runGit(['push', 'origin', branch]);
    return retry.exitCode == 0 ? null : retry.stderr.toString();
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

  Future<bool> _fileExists(String path) async =>
      File(path).exists();

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
