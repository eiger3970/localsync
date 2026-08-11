// services/sync_service.dart
//
// git2dart port of the original synco.sh-derived Dart port (which shelled
// out to `git`/`ssh` via Process.run - impossible on iOS, that file's own
// comment already flagged this). The conflict strategy below is unchanged
// from that version - only the git implementation moved from shelling out
// to git2dart FFI calls. See lib/STRUCTURE.md.
//
// 2026-08-15: split the old single fullSync() into genuinely separate
// pull()/push() operations, and moved the actual git work off the UI
// isolate. Two real bugs, both found from the same round of feedback:
//
// - "gitpull and gitpush are separate commands and don't do the same
//   thing" - true, and the old code didn't reflect that: fullSync()
//   always auto-detected direction and ran identically no matter which
//   UI gesture triggered it. pull() below only ever fetches+merges from
//   remote, never pushes. push() only ever pushes local commits, and
//   fails cleanly (asking for a pull first) on real divergence instead
//   of silently merging - that rejection is the actual behavioral
//   difference between `git pull` and `git push`, not something this
//   app should paper over with one do-everything function.
//
// - "tapping the repo row freezes the phone for 30 seconds" - a real
//   bug, not a missing spinner. git2dart's fetch()/push() are
//   synchronous FFI calls (confirmed against the package source,
//   git2dart-0.5.4/lib/src/remote.dart: `TransferProgress fetch(...)`,
//   not `Future<...>`) - calling them directly from Flutter's UI
//   isolate blocks all rendering and gesture handling for the entire
//   network round-trip. The git work below now runs inside compute(),
//   off the UI isolate. git2dart's Repository/Remote/etc. wrap native
//   pointers and can't cross an isolate boundary, so the whole
//   open-to-close git sequence for one sync runs self-contained inside
//   the isolate function - only plain data (paths, keys, a commit
//   message) goes in, and the existing SyncResult types (already plain
//   data, no native pointers) come back out. The tradeoff: no more
//   live "fetching.../committing.../pushing..." phase text mid-call,
//   since compute() returns one final result, not a stream of updates -
//   callers show a single phase for the operation's duration instead.
//   Same "don't fake progress you can't measure" reasoning as making
//   the setup flow's progress bar indeterminate instead of a fabricated
//   percentage.
//
// SyncPhase lives in models/repository.dart — not duplicated here.

import 'dart:io';
import 'package:flutter/foundation.dart' show compute;
import 'package:git2dart/git2dart.dart' as git;
import '../features/linking/linking_state.dart';
import '../models/repository.dart';
import 'vault_folder_service.dart';

// ── Result types ───────────────────────────────────────────────────────────────
// Plain data only, deliberately - these are the only things that cross
// the compute() isolate boundary back to the caller.

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
  final String? debugDetail;
  const SyncFailed(this.error, {this.debugDetail});
  String get diagnosis  => error.diagnosis;
  String get resolution => error.resolution;
}

class SyncEvent {
  final SyncPhase?  phase;
  final SyncResult? result;
  const SyncEvent({this.phase, this.result});
  factory SyncEvent.phase(SyncPhase p)  => SyncEvent(phase: p);
  factory SyncEvent.done(SyncResult r)  => SyncEvent(result: r);
}

// ── Params passed into the isolate ───────────────────────────────────────────
// Plain data only - git2dart objects don't cross isolates, so everything
// an isolate function needs travels in here instead of being read off
// `this`.

class _SyncParams {
  final String vaultPath;
  final String remoteUrl;
  final String remoteUser;
  final String branch;
  final String sshPrivateKeyPath;
  final String sshPublicKeyPath;
  final String sshPassphrase;
  final String commitMessage;
  const _SyncParams({
    required this.vaultPath,
    required this.remoteUrl,
    required this.remoteUser,
    required this.branch,
    required this.sshPrivateKeyPath,
    required this.sshPublicKeyPath,
    required this.sshPassphrase,
    required this.commitMessage,
  });
}

// ── SyncService ────────────────────────────────────────────────────────────────

class SyncService {
  final String vaultPath;
  final String vaultBookmark;
  final String remoteUser;
  final String remoteHost;
  final int    remotePort;
  final String remotePath;
  final String branch;
  final String sshPrivateKeyPath;
  final String sshPublicKeyPath;
  final String sshPassphrase;
  final VaultFolderService _vaultFolder;

  SyncService({
    required this.vaultPath,
    required this.vaultBookmark,
    required this.remoteUser,
    required this.remoteHost,
    required this.remotePath,
    required this.sshPrivateKeyPath,
    required this.sshPublicKeyPath,
    this.remotePort      = 22,
    this.branch           = 'main',
    this.sshPassphrase    = '',
    VaultFolderService? vaultFolder,
  }) : _vaultFolder = vaultFolder ?? VaultFolderService();

  factory SyncService.fromRepo(
    Repository repo, {
    required String sshPrivateKeyPath,
    required String sshPublicKeyPath,
  }) => SyncService(
    vaultPath:         repo.localPath,
    vaultBookmark:     repo.vaultBookmark,
    remoteUser:        repo.remoteUser,
    remoteHost:        repo.remoteHost,
    remotePath:        repo.remotePath,
    remotePort:        repo.remotePort,
    branch:            'main',
    sshPrivateKeyPath: sshPrivateKeyPath,
    sshPublicKeyPath:  sshPublicKeyPath,
  );

  String get _remoteUrl => 'ssh://$remoteUser@$remoteHost:$remotePort$remotePath';

  /// Bring remote changes down. Commits any dirty local tree first
  /// (established app behavior - doesn't block the user on git plumbing
  /// they don't understand), then fast-forwards if behind, merges
  /// (repairing conflicts in place) if diverged. Never pushes.
  Stream<SyncEvent> pull() => _run(_pullInIsolate, SyncPhase.pulling);

  /// Send local changes up. Commits any dirty local tree, fetches
  /// (needed to know whether a fast-forward push is even possible),
  /// then pushes if clean. On real divergence, fails cleanly asking for
  /// a pull first - matching real `git push`'s rejection - rather than
  /// silently merging on the user's behalf. [commitMessage] overrides
  /// the auto-generated timestamp, for the typed-message path.
  Stream<SyncEvent> push({String? commitMessage}) =>
      _run(_pushInIsolate, SyncPhase.pushing, commitMessage: commitMessage);

  Stream<SyncEvent> _run(
    Future<SyncResult> Function(_SyncParams) isolateFn,
    SyncPhase phase, {
    String? commitMessage,
  }) async* {
    if (vaultBookmark.isEmpty) {
      yield SyncEvent.done(const SyncFailed(LinkingError.vaultFolderAccessLost));
      return;
    }
    final resolvedPath = await _vaultFolder.startAccessing(vaultBookmark);
    if (resolvedPath == null) {
      yield SyncEvent.done(const SyncFailed(LinkingError.vaultFolderAccessLost));
      return;
    }
    try {
      yield SyncEvent.phase(phase);
      final params = _SyncParams(
        vaultPath: resolvedPath,
        remoteUrl: _remoteUrl,
        remoteUser: remoteUser,
        branch: branch,
        sshPrivateKeyPath: sshPrivateKeyPath,
        sshPublicKeyPath: sshPublicKeyPath,
        sshPassphrase: sshPassphrase,
        commitMessage: commitMessage ?? _timestamp(),
      );
      yield SyncEvent.done(await compute(isolateFn, params));
    } finally {
      await _vaultFolder.stopAccessing(vaultBookmark);
    }
  }

  // 2026-08-15: reformatted YYYY-MM-DD HH:MM:SS -> YYYYMMDDhhmm and
  // dropped the "synclocal " prefix, matching the user's own
  // established convention elsewhere (CommitScreen's own hint text,
  // real vault names like "202608111158").
  String _timestamp() {
    final n = DateTime.now();
    return '${n.year}${_p(n.month)}${_p(n.day)}${_p(n.hour)}${_p(n.minute)}';
  }

  String _p(int n) => n.toString().padLeft(2, '0');
}

// ── Isolate entry points ─────────────────────────────────────────────────────
// Top-level, not methods: compute() needs a top-level or static function
// with no captured state, since it runs in a fresh isolate that starts
// from scratch. Everything each one needs travels in via _SyncParams.

Future<SyncResult> _pullInIsolate(_SyncParams p) async {
  return _withRepo(p, (repo, remote, callbacks) {
    _commitDirtyTree(repo, p.commitMessage);

    remote.fetch(callbacks: callbacks);
    final remoteBranch = git.Branch.lookup(
      repo: repo, name: 'origin/${p.branch}', type: git.GitBranch.remote,
    );
    final localOid = repo.head.target;
    final remoteOid = remoteBranch.target;
    if (localOid == remoteOid) return const SyncNoChanges();

    final baseOid = git.Merge.base(repo, localOid, remoteOid);
    if (localOid == baseOid) {
      // Clean fast-forward - nothing local to preserve.
      repo.reset(oid: remoteOid, resetType: git.GitReset.hard);
      return const SyncOk('Downloaded latest notes');
    }
    if (remoteOid == baseOid) {
      // Remote has nothing new - local being ahead is push's job.
      return const SyncNoChanges();
    }

    // Diverged - three-way merge, conflicts repaired in place (both
    // versions kept), never aborted or silently dropped.
    final annotated = git.AnnotatedCommit.lookup(repo: repo, oid: remoteOid);
    git.Merge.commit(repo: repo, commit: annotated);
    if (repo.index.hasConflicts) _repairAllConflictsOnDisk(p.vaultPath);
    _finishMergeCommit(repo, message: 'Merge desktop and phone ${p.commitMessage}');
    repo.stateCleanup();
    return const SyncOk('Merged in changes from desktop');
  });
}

Future<SyncResult> _pushInIsolate(_SyncParams p) async {
  return _withRepo(p, (repo, remote, callbacks) {
    // 2026-08-16: "is this auto committing an auto timestamp... I
    // can't see?" - yes, and now the result says so explicitly (only
    // when a commit actually happened - if the tree was already
    // clean, p.commitMessage was never used, so don't claim it was).
    final committed = _commitDirtyTree(repo, p.commitMessage);

    remote.fetch(callbacks: callbacks);
    final remoteBranch = git.Branch.lookup(
      repo: repo, name: 'origin/${p.branch}', type: git.GitBranch.remote,
    );
    final localOid = repo.head.target;
    final remoteOid = remoteBranch.target;
    if (localOid == remoteOid) return const SyncNoChanges();

    final baseOid = git.Merge.base(repo, localOid, remoteOid);
    if (localOid == baseOid) {
      // Local has no commits of its own beyond what remote already has
      // - nothing to push, even if remote is ahead (that's pull's job).
      return const SyncNoChanges();
    }
    if (remoteOid != baseOid) {
      // Genuine divergence - both sides have unique commits. A real
      // `git push` is rejected here too; left for pull() to resolve,
      // not silently merged on push's behalf.
      return const SyncFailed(LinkingError.cannotFastForward);
    }

    final err = _pushWithRetry(repo, remote, callbacks, p.branch);
    if (err != null) return SyncFailed(err.error, debugDetail: err.detail);
    return SyncOk(committed
        ? 'Pushed as "${p.commitMessage}"'
        : 'Uploaded notes to desktop');
  });
}

/// Opens (or, if missing, freshly clones into) the vault's repo, runs
/// [op], and always frees the repo handle afterward. Shared by both
/// pull and push so the open/recover/close bracket lives in one place.
Future<SyncResult> _withRepo(
  _SyncParams p,
  SyncResult Function(git.Repository repo, git.Remote remote, git.Callbacks callbacks) op,
) async {
  final callbacks = git.Callbacks(
    credentials: git.Keypair(
      username: p.remoteUser,
      pubKey: p.sshPublicKeyPath,
      privateKey: p.sshPrivateKeyPath,
      passPhrase: p.sshPassphrase,
    ),
    // libgit2 has no known_hosts on iOS - without this every fetch/push
    // fails with "invalid or unknown remote ssh hostkey".
    certificateCheck: (certificate, host, {required valid}) => true,
  );

  // Fixed 2026-08-09: the app's own private storage does not survive
  // being reinstalled via sideloading (each new build wipes it), so a
  // missing .git here is routine after any rebuild, not a rare edge
  // case - recover the same way the initial setup clone does rather
  // than failing outright.
  if (!await Directory('${p.vaultPath}/.git').exists()) {
    try {
      final repo = git.Repository.init(
        path: p.vaultPath, initialHead: p.branch, originUrl: p.remoteUrl,
      );
      try {
        final remote = git.Remote.lookup(repo: repo, name: 'origin');
        remote.fetch(callbacks: callbacks);
        final remoteBranch = git.Branch.lookup(
          repo: repo, name: 'origin/${p.branch}', type: git.GitBranch.remote,
        );
        repo.reset(oid: remoteBranch.target, resetType: git.GitReset.hard);
      } finally {
        repo.free();
      }
      return const SyncOk('Downloaded your notes');
    } catch (e) {
      return SyncFailed(_diagnose(e), debugDetail: e.toString());
    }
  }

  late final git.Repository repo;
  try {
    repo = git.Repository.open(p.vaultPath);
  } catch (e) {
    return const SyncFailed(LinkingError.bareRepoNotFound);
  }

  try {
    // Recover from any stuck merge from a previous crashed run before
    // doing anything else.
    if (repo.state == git.GitRepositoryState.merge) {
      if (repo.index.hasConflicts) _repairAllConflictsOnDisk(p.vaultPath);
      _finishMergeCommit(repo);
      repo.stateCleanup();
    }
    final remote = git.Remote.lookup(repo: repo, name: 'origin');
    return op(repo, remote, callbacks);
  } catch (e) {
    return SyncFailed(_diagnose(e), debugDetail: e.toString());
  } finally {
    repo.free();
  }
}

/// Returns true if a commit was actually made (tree was dirty), false
/// if there was nothing to commit - callers use this to know whether
/// [message] genuinely became the new HEAD or was unused.
bool _commitDirtyTree(git.Repository repo, String message) {
  if (repo.status.isEmpty) return false;
  final headOid = repo.head.target;
  final parent  = git.Commit.lookup(repo: repo, oid: headOid);
  final tree    = _stageAndWriteTree(repo);
  git.Commit.create(
    repo: repo,
    updateRef: 'HEAD',
    author: _fixedSignature,
    committer: _fixedSignature,
    message: message,
    tree: tree,
    parents: [parent],
  );
  return true;
}

/// Completes an in-progress merge (from Merge.commit) by staging
/// whatever is in the working directory now (post-repair) and creating
/// the merge commit with both parents.
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
    author: _fixedSignature,
    committer: _fixedSignature,
    message: message ?? 'Merge conflicts (both sides kept) ${_isolateTimestamp()}',
    tree: tree,
    parents: [localCommit, remoteCommit],
  );
}

// Same YYYYMMDDhhmm format as SyncService._timestamp() - duplicated as
// a tiny top-level function rather than shared, since this runs inside
// the isolate and can't reach an instance method on the main-isolate
// SyncService object.
String _isolateTimestamp() {
  final n = DateTime.now();
  String p2(int v) => v.toString().padLeft(2, '0');
  return '${n.year}${p2(n.month)}${p2(n.day)}${p2(n.hour)}${p2(n.minute)}';
}

git.Tree _stageAndWriteTree(git.Repository repo) {
  final index = repo.index;
  index.addAll(['*']);
  index.write();
  final treeOid = index.writeTree(repo);
  return git.Tree.lookup(repo: repo, oid: treeOid);
}

// Fixed local identity, same convention the old Working Copy resolution
// text used to tell users to type in manually - the app sets this
// itself now, nothing to ask the user for.
git.Signature get _fixedSignature =>
    git.Signature.create(name: 'Synclocal', email: 'synclocal@device.local');

/// Push with one retry on non-fast-forward rejection (remote moved
/// between our fetch and this push - re-fetch and fast-forward if
/// possible, then retry once). A genuine divergence found here is left
/// for the next pull() to resolve, not duplicated as merge logic here.
({LinkingError error, String detail})? _pushWithRetry(
  git.Repository repo,
  git.Remote remote,
  git.Callbacks callbacks,
  String branch,
) {
  try {
    remote.push(
      refspecs: ['refs/heads/$branch:refs/heads/$branch'],
      callbacks: callbacks,
    );
    return null;
  } catch (e) {
    try {
      remote.fetch(callbacks: callbacks);
      final remoteBranch = git.Branch.lookup(
        repo: repo, name: 'origin/$branch', type: git.GitBranch.remote,
      );
      final analysis = git.Merge.analysis(repo: repo, theirHead: remoteBranch.target);
      if (!analysis.result.contains(git.GitMergeAnalysis.fastForward)) {
        return (error: LinkingError.cannotFastForward, detail: e.toString());
      }
      repo.reset(oid: remoteBranch.target, resetType: git.GitReset.hard);
      remote.push(
        refspecs: ['refs/heads/$branch:refs/heads/$branch'],
        callbacks: callbacks,
      );
      return null;
    } catch (e2) {
      return (error: _diagnose(e2), detail: e2.toString());
    }
  }
}

// ── Conflict repair — ports repair_conflicts.py's text strategy verbatim,
//    just triggered after git2dart's Merge.commit instead of `git merge`.
//    Operates on working-directory files as plain text, not git's index/
//    tree objects, so nothing here needed the low-level conflict API. ────

void _repairAllConflictsOnDisk(String path) {
  final dir = Directory(path);
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
           '> [!warning]+ SYNC CONFLICT - other device version (review and delete one)\n'
           '$callout\n\n';
  });
}

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
