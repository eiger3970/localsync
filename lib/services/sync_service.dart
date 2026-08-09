// services/sync_service.dart
//
// git2dart port of the original synco.sh-derived Dart port (which shelled
// out to `git`/`ssh` via Process.run - impossible on iOS, that file's own
// comment already flagged this). The phase flow and conflict strategy below
// are unchanged from that version - only the git implementation moved from
// shelling out to git2dart FFI calls. See lib/STRUCTURE.md.
//
// SyncPhase lives in models/repository.dart — not duplicated here.

import 'dart:io';
import 'package:git2dart/git2dart.dart' as git;
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
  final String sshPrivateKeyPath;
  final String sshPublicKeyPath;
  final String sshPassphrase;

  SyncService({
    required this.vaultPath,
    required this.remoteUser,
    required this.remoteHost,
    required this.sshPrivateKeyPath,
    required this.sshPublicKeyPath,
    this.remotePort      = 22,
    this.branch           = 'main',
    this.sshPassphrase    = '',
  });

  factory SyncService.fromRepo(
    Repository repo, {
    required String sshPrivateKeyPath,
    required String sshPublicKeyPath,
  }) => SyncService(
    // Fixed 2026-08-09: this was repo.obsidianVaultPath, a cosmetic
    // Files-app display label ("On My iPhone/Synclocal"), not a real
    // filesystem path - every sync failed with bareRepoNotFound
    // immediately, regardless of network. repo.localPath is the real
    // on-disk absolute path. See models/repository.dart.
    vaultPath:         repo.localPath,
    remoteUser:        repo.remoteUser,
    remoteHost:        repo.remoteHost,
    remotePort:        repo.remotePort,
    branch:            'main',
    sshPrivateKeyPath: sshPrivateKeyPath,
    sshPublicKeyPath:  sshPublicKeyPath,
  );

  git.Credentials get _credentials => git.Keypair(
        username: remoteUser,
        pubKey: sshPublicKeyPath,
        privateKey: sshPrivateKeyPath,
        passPhrase: sshPassphrase,
      );

  git.Callbacks get _callbacks => git.Callbacks(credentials: _credentials);

  // Fixed local identity, same convention the old Working Copy resolution
  // text used to tell users to type in manually ("Git phone obsidian" /
  // "phone@obsidian.local") - the app sets this itself now, nothing to ask
  // the user for.
  git.Signature get _signature =>
      git.Signature.create(name: 'Synclocal', email: 'synclocal@device.local');

  // ── Full sync ──────────────────────────────────────────────────────────────

  Stream<SyncEvent> fullSync({String? commitMessage}) async* {
    if (!await Directory('$vaultPath/.git').exists()) {
      yield SyncEvent.done(const SyncFailed(LinkingError.bareRepoNotFound));
      return;
    }

    late final git.Repository repo;
    try {
      repo = git.Repository.open(vaultPath);
    } catch (e) {
      yield SyncEvent.done(const SyncFailed(LinkingError.bareRepoNotFound));
      return;
    }

    try {
      // 1. Recover from any stuck merge from a previous crashed run
      if (repo.state == git.GitRepositoryState.merge) {
        _repairAllConflictsOnDisk();
        if (repo.index.hasConflicts) {
          // Repair pass found nothing new to fix but conflicts remain -
          // same "tree was clean but merge not committed" edge case the
          // shell version handled by committing anyway.
        }
        _finishMergeCommit(repo);
        repo.stateCleanup();
      }

      // 2. Commit any unsaved local changes
      yield SyncEvent.phase(SyncPhase.detecting);
      if (repo.status.isNotEmpty) {
        yield SyncEvent.phase(SyncPhase.committing);
        _commitAll(repo, commitMessage ?? 'synclocal ${_timestamp()}');
      }

      // 3. Fetch
      yield SyncEvent.phase(SyncPhase.fetching);
      final remote = git.Remote.lookup(repo: repo, name: 'origin');
      remote.fetch(callbacks: _callbacks);

      // 4. Compare LOCAL / REMOTE / BASE
      final localOid  = repo.head.target;
      final remoteBranch = git.Branch.lookup(
        repo: repo,
        name: 'origin/$branch',
        type: git.GitBranch.remote,
      );
      final remoteOid = remoteBranch.target;
      final baseOid    = git.Merge.base(repo, localOid, remoteOid);

      if (localOid == remoteOid) {
        yield SyncEvent.done(const SyncNoChanges());
        return;
      }

      if (localOid == baseOid) {
        yield SyncEvent.phase(SyncPhase.pulling);
        repo.reset(oid: remoteOid, resetType: git.GitReset.hard);
        yield SyncEvent.done(const SyncOk('Downloaded latest notes'));
        return;
      }

      if (remoteOid == baseOid) {
        yield SyncEvent.phase(SyncPhase.pushing);
        final err = _pushWithRetry(repo, remote);
        if (err != null) {
          yield SyncEvent.done(SyncFailed(err));
          return;
        }
        yield SyncEvent.done(const SyncOk('Uploaded notes to desktop'));
        return;
      }

      // Diverged — three-way merge. Conflicts are not aborted: repaired in
      // place (both versions kept, other side quoted in an Obsidian
      // callout) so nothing is ever silently lost, then committed.
      yield SyncEvent.phase(SyncPhase.merging);
      final annotated = git.AnnotatedCommit.lookup(repo: repo, oid: remoteOid);
      git.Merge.commit(repo: repo, commit: annotated);

      if (repo.index.hasConflicts) {
        _repairAllConflictsOnDisk();
      }
      _finishMergeCommit(repo, message: 'Merge desktop and phone ${_timestamp()}');
      repo.stateCleanup();

      final pushErr = _pushWithRetry(repo, remote);
      if (pushErr != null) {
        yield SyncEvent.done(SyncFailed(pushErr));
        return;
      }
      yield SyncEvent.done(const SyncOk('Merged and synced'));
    } catch (e) {
      yield SyncEvent.done(SyncFailed(_diagnose(e)));
    } finally {
      repo.free();
    }
  }

  // ── Conflict repair — ports repair_conflicts.py's text strategy verbatim,
  //    just triggered after git2dart's Merge.commit instead of `git merge`.
  //    Operates on working-directory files as plain text, not git's index/
  //    tree objects, so nothing here needed the low-level conflict API. ────

  void _repairAllConflictsOnDisk() {
    final dir = Directory(vaultPath);
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.md')) continue;
      try {
        final content = entity.readAsStringSync();
        if (!content.contains('<<<<<<< ')) continue;
        entity.writeAsStringSync(_repairConflictMarkers(content));
      } catch (_) {
        // Skip unreadable files
      }
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

  // ── Commit helpers ───────────────────────────────────────────────────────────

  void _commitAll(git.Repository repo, String message) {
    final headOid = repo.head.target;
    final parent  = git.Commit.lookup(repo: repo, oid: headOid);
    final tree    = _stageAndWriteTree(repo);
    git.Commit.create(
      repo: repo,
      updateRef: 'HEAD',
      author: _signature,
      committer: _signature,
      message: message,
      tree: tree,
      parents: [parent],
    );
  }

  /// Completes an in-progress merge (from Merge.commit) by staging whatever
  /// is in the working directory now (post-repair) and creating the merge
  /// commit with both parents.
  void _finishMergeCommit(git.Repository repo, {String? message}) {
    final localOid = repo.head.target;
    final git.Oid remoteOid;
    try {
      remoteOid = git.Reference.lookup(repo: repo, name: 'MERGE_HEAD').target;
    } catch (_) {
      return; // nothing to finish - not actually mid-merge
    }

    final localCommit  = git.Commit.lookup(repo: repo, oid: localOid);
    final remoteCommit = git.Commit.lookup(repo: repo, oid: remoteOid);
    final tree          = _stageAndWriteTree(repo);

    git.Commit.create(
      repo: repo,
      updateRef: 'HEAD',
      author: _signature,
      committer: _signature,
      message: message ?? 'Merge conflicts (both sides kept) ${_timestamp()}',
      tree: tree,
      parents: [localCommit, remoteCommit],
    );
  }

  git.Tree _stageAndWriteTree(git.Repository repo) {
    final index = repo.index;
    index.addAll(['*']);
    index.write();
    final treeOid = index.writeTree(repo);
    return git.Tree.lookup(repo: repo, oid: treeOid);
  }

  // ── Push with one retry on non-fast-forward rejection ─────────────────────

  LinkingError? _pushWithRetry(git.Repository repo, git.Remote remote) {
    try {
      remote.push(
        refspecs: ['refs/heads/$branch:refs/heads/$branch'],
        callbacks: _callbacks,
      );
      return null;
    } catch (e) {
      // Remote moved since our fetch — fetch again and fast-forward if
      // possible, then retry once. A genuine divergence here is left for
      // the next fullSync() call to handle via the real merge path above,
      // rather than duplicating that logic mid-push.
      try {
        remote.fetch(callbacks: _callbacks);
        final remoteBranch = git.Branch.lookup(
          repo: repo,
          name: 'origin/$branch',
          type: git.GitBranch.remote,
        );
        final analysis = git.Merge.analysis(
          repo: repo,
          theirHead: remoteBranch.target,
        );
        if (!analysis.result.contains(git.GitMergeAnalysis.fastForward)) {
          return LinkingError.cannotFastForward;
        }
        repo.reset(oid: remoteBranch.target, resetType: git.GitReset.hard);
        remote.push(
          refspecs: ['refs/heads/$branch:refs/heads/$branch'],
          callbacks: _callbacks,
        );
        return null;
      } catch (e2) {
        return _diagnose(e2);
      }
    }
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  String _timestamp() {
    final n = DateTime.now();
    return '${n.year}-${_p(n.month)}-${_p(n.day)} '
           '${_p(n.hour)}:${_p(n.minute)}:${_p(n.second)}';
  }

  String _p(int n) => n.toString().padLeft(2, '0');

  LinkingError _diagnose(Object e) {
    final msg = e.toString();
    if (msg.contains('Connection refused') ||
        msg.contains('No route to host') ||
        msg.contains('failed to connect') ||
        msg.contains('timed out'))        return LinkingError.connectionRefused;
    if (msg.contains('authentication') ||
        msg.contains('Auth') ||
        msg.contains('publickey'))        return LinkingError.sshAuthFailed;
    if (msg.contains('does not appear to be a git repository') ||
        msg.contains('repository not found')) return LinkingError.bareRepoNotFound;
    if (msg.contains('non-fast-forward') ||
        msg.contains('fast-forward'))     return LinkingError.cannotFastForward;
    if (msg.contains('index is locked') ||
        msg.contains('index.lock'))       return LinkingError.indexLocked;
    return LinkingError.mergeConflict;
  }
}
