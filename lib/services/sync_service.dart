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
import 'binary_conflict_log.dart';
import 'conflict_repair.dart';
import 'vault_backup.dart';
import 'vault_folder_service.dart';

// ── Result types ───────────────────────────────────────────────────────────────
// Plain data only, deliberately - these are the only things that cross
// the compute() isolate boundary back to the caller.

sealed class SyncResult {
  const SyncResult();
}

class SyncOk extends SyncResult {
  final String message;
  const SyncOk(this.message);
}

class SyncNoChanges extends SyncResult {
  const SyncNoChanges();
}

// 2026-08-19: real user finding, walked through the actual flow live -
// "way too convoluted, automate it." A pull that produced a real,
// still-unresolved conflict used to return the exact same SyncOk as
// any other clean pull ("Merged in changes from desktop") - nothing on
// screen said a decision was needed, so the only way to ever discover
// a conflict was already knowing to check a menu with no badge on it.
// This carries how many files actually need review, straight from
// repairAllConflictsOnDisk's own count - not a guess, not a separate
// re-scan - so the caller can both say so honestly and navigate
// straight into the Conflicts screen instead of a dead-end success
// message. Replaces the old SyncConflict class, which existed for
// this same purpose but was never actually returned by pull() -
// permanently dead code from before the conflict-picker feature
// existed, and modeled as a failure besides, which this isn't: the
// merge itself succeeded, the conflict is fully backed up and
// resolvable, this is a followup action, not an error.
class SyncOkWithConflicts extends SyncResult {
  final int conflictCount;
  const SyncOkWithConflicts(this.conflictCount);
}

class SyncFailed extends SyncResult {
  final LinkingError error;
  final String? debugDetail;
  const SyncFailed(this.error, {this.debugDetail});
  String get diagnosis => error.diagnosis;
  String get resolution => error.resolution;
}

/// 2026-08-18: a pull/push that would delete a large chunk of existing
/// content used to fast-forward silently, same as any other clean sync -
/// no different from adding one new note. Real fear behind this: one
/// device gets emptied by mistake, then a normal-looking sync (no
/// conflict, nothing to repair) propagates that emptiness and wipes the
/// other device's real data too. Callers must stop and show [summary],
/// then re-run the same pull()/push() with confirmed:true if the user
/// agrees - see _isLargeDeletion below for the threshold.
class SyncNeedsConfirmation extends SyncResult {
  // Paths, not just counts - "sometimes users need to know more than a
  // number" (2026-08-18). The plain-language summary stays the default
  // view; these back an optional drill-down the dialog can show on
  // request, so the default case is still a one-line read.
  final List<String> addedFiles;
  final List<String> removedFiles;
  final List<String> modifiedFiles;
  const SyncNeedsConfirmation({
    this.addedFiles = const [],
    this.removedFiles = const [],
    this.modifiedFiles = const [],
  });

  int get filesAdded => addedFiles.length;
  int get filesRemoved => removedFiles.length;
  int get filesModified => modifiedFiles.length;

  String get summary {
    final parts = <String>[];
    if (filesRemoved > 0) {
      parts.add('remove $filesRemoved file${filesRemoved == 1 ? '' : 's'}');
    }
    if (filesAdded > 0) {
      parts.add('add $filesAdded file${filesAdded == 1 ? '' : 's'}');
    }
    if (filesModified > 0) {
      parts.add('change $filesModified file${filesModified == 1 ? '' : 's'}');
    }
    return 'This sync will ${parts.join(', ')}. Continue?';
  }
}

class SyncEvent {
  final SyncPhase? phase;
  final SyncResult? result;
  const SyncEvent({this.phase, this.result});
  factory SyncEvent.phase(SyncPhase p) => SyncEvent(phase: p);
  factory SyncEvent.done(SyncResult r) => SyncEvent(result: r);
}

/// Single source of truth for turning a SyncResult into user-facing text -
/// shared by every screen that runs a sync so results can never drift out
/// of sync with each other again (home_screen.dart's SnackBar and
/// commit_screen.dart's silently-discarded result used to each need their
/// own copy of this).
String syncResultMessage(SyncResult result) => switch (result) {
      SyncOk(:final message) => message,
      SyncNoChanges() => 'Nothing to sync.',
      SyncOkWithConflicts(:final conflictCount) => conflictCount == 1
          ? 'Merged in changes - 1 file needs your review.'
          : 'Merged in changes - $conflictCount files need your review.',
      SyncFailed(:final diagnosis) => diagnosis,
      SyncNeedsConfirmation(:final summary) => summary,
    };

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
  final String deviceName;
  final bool confirmed;
  const _SyncParams({
    required this.vaultPath,
    required this.remoteUrl,
    required this.remoteUser,
    required this.branch,
    required this.sshPrivateKeyPath,
    required this.sshPublicKeyPath,
    required this.sshPassphrase,
    required this.commitMessage,
    required this.deviceName,
    this.confirmed = false,
  });
}

// ── SyncService ────────────────────────────────────────────────────────────────

class SyncService {
  final String vaultPath;
  final String vaultBookmark;
  final String remoteUser;
  final String remoteHost;
  final int remotePort;
  final String remotePath;
  final String branch;
  final String sshPrivateKeyPath;
  final String sshPublicKeyPath;
  final String sshPassphrase;
  // 2026-08-18: the git commit author name for this device - see
  // _signatureFor below. Plain data, read from DatabaseService by the
  // caller before constructing this (SharedPreferences can't be reached
  // from inside compute()'s isolate, same reason every other value here
  // is passed in rather than looked up on demand).
  final String deviceName;
  final VaultFolderService _vaultFolder;

  SyncService({
    required this.vaultPath,
    required this.vaultBookmark,
    required this.remoteUser,
    required this.remoteHost,
    required this.remotePath,
    required this.sshPrivateKeyPath,
    required this.sshPublicKeyPath,
    required this.deviceName,
    this.remotePort = 22,
    this.branch = 'main',
    this.sshPassphrase = '',
    VaultFolderService? vaultFolder,
  }) : _vaultFolder = vaultFolder ?? VaultFolderService();

  factory SyncService.fromRepo(
    Repository repo, {
    required String sshPrivateKeyPath,
    required String sshPublicKeyPath,
    required String deviceName,
  }) =>
      SyncService(
        vaultPath: repo.localPath,
        vaultBookmark: repo.vaultBookmark,
        remoteUser: repo.remoteUser,
        remoteHost: repo.remoteHost,
        remotePath: repo.remotePath,
        remotePort: repo.remotePort,
        branch: 'main',
        sshPrivateKeyPath: sshPrivateKeyPath,
        sshPublicKeyPath: sshPublicKeyPath,
        deviceName: deviceName,
      );

  String get _remoteUrl =>
      'ssh://$remoteUser@$remoteHost:$remotePort$remotePath';

  /// Bring remote changes down. Commits any dirty local tree first
  /// (established app behavior - doesn't block the user on git plumbing
  /// they don't understand), then fast-forwards if behind, merges
  /// (repairing conflicts in place) if diverged. Never pushes.
  /// [confirmed] skips the deletion-safety check below (see
  /// SyncNeedsConfirmation) - pass true only on a second call after the
  /// user has already seen and agreed to the summary from the first.
  Stream<SyncEvent> pull({bool confirmed = false}) =>
      _run(_pullInIsolate, SyncPhase.pulling, confirmed: confirmed);

  /// Send local changes up. Commits any dirty local tree, fetches
  /// (needed to know whether a fast-forward push is even possible),
  /// then pushes if clean. On real divergence, fails cleanly asking for
  /// a pull first - matching real `git push`'s rejection - rather than
  /// silently merging on the user's behalf. [commitMessage] overrides
  /// the auto-generated timestamp, for the typed-message path.
  /// [confirmed] - see pull() above.
  Stream<SyncEvent> push({String? commitMessage, bool confirmed = false}) =>
      _run(_pushInIsolate, SyncPhase.pushing,
          commitMessage: commitMessage, confirmed: confirmed);

  Stream<SyncEvent> _run(
    Future<SyncResult> Function(_SyncParams) isolateFn,
    SyncPhase phase, {
    String? commitMessage,
    bool confirmed = false,
  }) async* {
    if (vaultBookmark.isEmpty) {
      yield SyncEvent.done(
          const SyncFailed(LinkingError.vaultFolderAccessLost));
      return;
    }
    final resolvedPath = await _vaultFolder.startAccessing(vaultBookmark);
    if (resolvedPath == null) {
      yield SyncEvent.done(
          const SyncFailed(LinkingError.vaultFolderAccessLost));
      return;
    }
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
      deviceName: deviceName,
      confirmed: confirmed,
    );
    // 2026-08-19: real device bug, found chasing "the conflict this
    // pull just created doesn't show up in the Conflicts screen it
    // auto-navigates to" - stopAccessing() used to run in a `finally`
    // AFTER the `yield SyncEvent.done(...)` above. RepositoryProvider's
    // `await for` loop returns as soon as it sees that done event
    // (case SyncOkWithConflicts(): ...; return result;) - which cancels
    // this generator's subscription, triggering the finally block, but
    // does NOT wait for that cancellation's cleanup to actually finish
    // before the caller's own Future resolves. So a caller could
    // already be acting on the result - in this case, immediately
    // starting a *fresh* startAccessing() for ConflictsScreen's own
    // scan - while this pull's stopAccessing() on the very same
    // bookmark was still in flight. Computing the result and releasing
    // access BEFORE yielding the done event removes that race
    // entirely, regardless of how a consumer handles stream
    // cancellation.
    SyncResult result;
    try {
      result = await compute(isolateFn, params);
    } finally {
      await _vaultFolder.stopAccessing(vaultBookmark);
    }
    yield SyncEvent.done(result);
  }

  // 2026-08-15: reformatted YYYY-MM-DD HH:MM:SS -> YYYYMMDDhhmm and
  // dropped the "localsync " prefix, matching the user's own
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
//
// 2026-09-05: real bug found chasing a live repro - git2dart's Tree
// operator[] multi-segment path lookup ("Journal/2026/09/Sep 5th,
// 2026.md") threw "the path 'Sep 5th, 2026.md' does not exist", quietly
// dropping the directory prefix from its own error - a binding-level
// bug, not proof the file was actually missing. Walks one path segment
// at a time instead, using single-name lookups only (never the '/'-
// path form), which sidesteps whatever that binding does wrong with
// nested paths.
git.Oid? _lookupPathOid(git.Repository repo, git.Tree rootTree, String path) {
  var currentTree = rootTree;
  final segments = path.split('/');
  for (var i = 0; i < segments.length; i++) {
    git.TreeEntry entry;
    try {
      entry = currentTree[segments[i]];
    } catch (_) {
      return null;
    }
    if (i == segments.length - 1) return entry.oid;
    final obj = entry.toObject(repo);
    if (obj is git.Tree) {
      currentTree = obj;
    } else {
      return null;
    }
  }
  return null;
}

// 2026-08-26: commitDirtyTree/labelForCommit/repairAllConflictsOnDisk/
// finishMergeCommit below were library-private until now - made public
// (name unchanged, just dropped the leading underscore) so git_service.dart's
// pullFromBareRepo() can reuse this exact merge-and-repair pipeline for the
// initial-link case instead of a second, drifting copy - real feedback,
// live: linking a real, already-used vault folder hit LinkingError
// .mergeConflict, which used to just fail outright (deferred scope,
// 2026-08-08) instead of doing the same safe three-way merge ordinary
// day-to-day pulls already do here.

Future<SyncResult> _pullInIsolate(_SyncParams p) async {
  return _withRepo(p, (repo, remote, callbacks) {
    commitDirtyTree(repo, p.commitMessage, p.deviceName);

    // 2026-08-30: real device bug - "cannot locate remote-tracking branch
    // origin/main," repeated after git_service.dart's own fix to the
    // linking-time version of this same pattern. This is the real day-
    // to-day pull path (an auto-sync on launch can hit it seconds after
    // a brand new repo is linked, before any push has happened) - a
    // fresh bare repo has no branches at all until pushed to, but
    // Branch.lookup ran unconditionally right after fetch(). remote.ls()
    // checks what's actually there first, same pattern already used in
    // git_service.dart's getStatus/pullFromBareRepo.
    final remoteRefs = remote.ls(callbacks: callbacks);
    final hasRemoteBranch =
        remoteRefs.any((r) => r.name == 'refs/heads/${p.branch}');
    // 2026-09-05: temporary diagnostic - real device retest of the
    // divergence fix still silently said "Nothing to sync," need to
    // know which branch is actually firing before guessing further.
    if (!hasRemoteBranch) return SyncOk('DIAG: no remote branch');
    final liveServerOid =
        remoteRefs.firstWhere((r) => r.name == 'refs/heads/${p.branch}').oid;
    final refspecsBefore = remote.fetchRefspecs;
    remote.fetch(callbacks: callbacks);
    final remoteBranch = git.Branch.lookup(
      repo: repo,
      name: 'origin/${p.branch}',
      type: git.GitBranch.remote,
    );
    // 2026-09-05: temporary diagnostic - real device confirmed the
    // tracking-ref resolution (Branch.lookup 'origin/main') is stuck 39
    // commits behind the true current tip, across multiple fetches.
    // remote.ls() above is a live, always-accurate server listing
    // (confirmed separately) - comparing its oid against what
    // Branch.lookup resolves to, plus the configured fetch refspecs,
    // settles whether fetch() is retrieving the right data but failing
    // to update the tracking ref (a refspec config issue, possibly
    // fixable), or something deeper.
    if (liveServerOid != remoteBranch.target) {
      return SyncOk('DIAG: live server oid=$liveServerOid differs from '
          'tracking ref oid=${remoteBranch.target} after fetch - '
          'refspecs=$refspecsBefore');
    }
    final localOid = repo.head.target;
    final remoteOid = remoteBranch.target;
    if (localOid == remoteOid) {
      return SyncOk('DIAG: localOid==remoteOid, both '
          '${localOid.toString().substring(0, 10)}');
    }

    final baseOid = git.Merge.base(repo, localOid, remoteOid);
    if (localOid == baseOid) {
      // Clean fast-forward - nothing local to preserve, so this is
      // exactly the "normal-looking, no conflict" case the deletion
      // check exists for.
      if (!p.confirmed) {
        final counts = _diffFileCounts(repo, localOid, remoteOid);
        if (_isLargeDeletion(counts)) {
          return SyncNeedsConfirmation(
            addedFiles: counts.added,
            removedFiles: counts.removed,
            modifiedFiles: counts.modified,
          );
        }
      }
      repo.reset(oid: remoteOid, resetType: git.GitReset.hard);
      return const SyncOk('Downloaded latest notes.');
    }
    if (remoteOid == baseOid) {
      // 2026-09-05: REAL BUG, confirmed live with a real user's own
      // diary content - "local ahead of remote" (per git's commit-graph
      // ancestry) was being trusted as proof there's nothing left to
      // reconcile. That assumption is wrong: commitDirtyTree runs
      // BEFORE this fetch/comparison, so the local "ahead" commit can
      // legitimately be a real ancestor of remote graph-wise while its
      // own file content has already silently diverged from whatever
      // the remote independently holds for the same path right now -
      // confirmed live: the phone's own real diary entry for today
      // silently raced ahead of the desktop's own real, different entry
      // for the same file, and a real push from this state would have
      // silently overwritten the desktop's content with zero warning,
      // zero conflict, zero backup.
      //
      // Real constraint on this fix: git2dart's own Merge.commit() is
      // ancestor-aware, same as the check above - it would treat this
      // exact case as "already up to date" and do nothing, since remote
      // genuinely is an ancestor of local. A real three-way merge here
      // needs Merge.trees()/manual index+checkout+MERGE_HEAD plumbing
      // that can't be verified against real git2dart behavior on this
      // Pi (git2dart's bundled binaries are x86_64-only, this hardware
      // is arm64 - the same reason flutter test can't run any
      // git2dart-touching test locally, documented elsewhere in this
      // app's history). Shipping an unverified hand-rolled merge
      // sequence against a real user's only copy of irreplaceable
      // content is a worse risk than not auto-merging at all.
      //
      // Safe fix instead: detect the missed divergence (pure read-only
      // tree/blob comparison, no working-tree or repo mutation - low
      // risk), and if found, back up the remote's independent content
      // using this app's own already-proven backup mechanism (same
      // pattern as _resolveBinaryConflict below) rather than silently
      // declaring nothing to sync. Local's own content is never touched
      // - nothing is lost either way, the user gets an honest signal
      // and both real versions to combine by hand instead of one
      // silently winning over the other.
      final divergedPaths = <String>[];
      // 2026-09-05: temporary diagnostic, real device retest of the
      // 7b5c6a8/b587154 fix still silently said "Nothing to sync" -
      // this is now visible in every case, not just failures, to prove
      // whether this block even runs and what the lookups actually
      // return, instead of guessing at a third theory blind.
      var diag = 'remoteOid=$remoteOid baseOid=$baseOid';
      try {
        final localCommit = git.Commit.lookup(repo: repo, oid: localOid);
        final parentOid = localCommit.parents.first;
        diag += ' parentOid=$parentOid';
        final locallyChanged = _diffFileCounts(repo, parentOid, localOid);
        final remoteTree = git.Commit.lookup(repo: repo, oid: remoteOid).tree;
        final parentTree = git.Commit.lookup(repo: repo, oid: parentOid).tree;
        diag += ' remoteTree.length=${remoteTree.length} parentTree.length=${parentTree.length}';
        final changedPaths = {
          ...locallyChanged.added,
          ...locallyChanged.removed,
          ...locallyChanged.modified
        };
        diag += ' changed=${changedPaths.join("|")}';
        for (final path in changedPaths) {
          final remoteEntryOid = _lookupPathOid(repo, remoteTree, path);
          final parentEntryOid = _lookupPathOid(repo, parentTree, path);
          diag += ' [$path remote=${remoteEntryOid?.toString().substring(0, 8) ?? "null"} '
              'parent=${parentEntryOid?.toString().substring(0, 8) ?? "null"}]';
          // Remote independently has this path with content that isn't
          // what local's own history started from - a real, missed
          // conflict, not a false alarm.
          if (remoteEntryOid != null && remoteEntryOid != parentEntryOid) {
            divergedPaths.add(path);
          }
        }
      } catch (e) {
        diag = 'exception: $e';
      }
      if (divergedPaths.isEmpty) return SyncOk('DIAG (nothing to sync): $diag');

      final backupDir =
          Directory('${p.vaultPath}/$kLocalSyncFolderName/Conflict Backups');
      backupDir.createSync(recursive: true);
      final ts = backupTimestamp();
      final remoteTree = git.Commit.lookup(repo: repo, oid: remoteOid).tree;
      final savedNames = <String>[];
      for (final path in divergedPaths) {
        try {
          final entryOid = _lookupPathOid(repo, remoteTree, path);
          if (entryOid == null) continue;
          final blob = git.Blob.lookup(repo: repo, oid: entryOid);
          final rawName = path.split('/').last;
          final dot = rawName.lastIndexOf('.');
          final stem = dot > 0 ? rawName.substring(0, dot) : rawName;
          final ext = dot > 0 ? rawName.substring(dot) : '';
          final backupName = '$stem - desktop version - $ts$ext';
          File('${backupDir.path}/$backupName').writeAsBytesSync(blob.contentBytes);
          savedNames.add(backupName);
        } catch (_) {
          // Leave this one path unreported rather than guess at content.
        }
      }
      return SyncOk(
          'Pull stopped: ${divergedPaths.join(", ")} has different real '
          'content on the desktop that couldn\'t be safely combined '
          'automatically. Saved the desktop\'s version to LocalSync/'
          'Conflict Backups (${savedNames.join(", ")}) - please combine '
          'both by hand before syncing further.');
    }

    // Diverged - three-way merge, conflicts repaired in place (both
    // versions kept), never aborted or silently dropped.
    final annotated = git.AnnotatedCommit.lookup(repo: repo, oid: remoteOid);
    git.Merge.commit(repo: repo, commit: annotated);
    var unresolvedCount = 0;
    if (repo.index.hasConflicts) {
      final other = labelForCommit(repo, remoteOid);
      unresolvedCount = repairAllConflictsOnDisk(p.vaultPath,
          otherLabel: other.label,
          otherTime: other.time.isEmpty ? null : other.time);
    }
    finishMergeCommit(repo, p.deviceName,
        message: 'Merge desktop and phone ${p.commitMessage}');
    repo.stateCleanup();
    if (unresolvedCount > 0) return SyncOkWithConflicts(unresolvedCount);
    return const SyncOk('Merged in changes from desktop.');
  });
}

Future<SyncResult> _pushInIsolate(_SyncParams p) async {
  return _withRepo(p, (repo, remote, callbacks) {
    // 2026-08-16: "is this auto committing an auto timestamp... I
    // can't see?" - yes, and now the result says so explicitly (only
    // when a commit actually happened - if the tree was already
    // clean, p.commitMessage was never used, so don't claim it was).
    final committed = commitDirtyTree(repo, p.commitMessage, p.deviceName);

    // 2026-08-30: same real bug/fix as _pullInIsolate above - a fresh
    // bare repo has no branches until something is actually pushed to
    // it, so the unconditional fetch+lookup below threw here too on a
    // genuinely empty remote. No remote branch means this push IS what
    // establishes it - nothing to diff/compare against yet, so this
    // skips straight to the push itself instead of a fetch/lookup that
    // can only fail.
    final remoteRefs = remote.ls(callbacks: callbacks);
    final hasRemoteBranch =
        remoteRefs.any((r) => r.name == 'refs/heads/${p.branch}');
    if (!hasRemoteBranch) {
      final err = _pushWithRetry(repo, remote, callbacks, p.branch);
      if (err != null) return SyncFailed(err.error, debugDetail: err.detail);
      return SyncOk(committed
          ? 'Pushed as "${p.commitMessage}".'
          : 'Uploaded notes to desktop.');
    }
    remote.fetch(callbacks: callbacks);
    final remoteBranch = git.Branch.lookup(
      repo: repo,
      name: 'origin/${p.branch}',
      type: git.GitBranch.remote,
    );
    final localOid = repo.head.target;
    final remoteOid = remoteBranch.target;
    if (localOid == remoteOid) {
      // 2026-08-14: was a raw diagnostic dump here (vault path, git2dart
      // status, a full filesystem listing) - real feedback, live,
      // 2026-08-26: "Nothing to sync - path=/private/var/...bla bla bla
      // for the entire phone screen." That diagnostic was tracking a
      // real bug (a genuinely new note not being detected as a change)
      // that commitDirtyTree's always-stage-and-compare-tree-hash fix
      // (see its own doc comment) already resolved - this branch
      // reaching localOid == remoteOid now really does mean nothing
      // changed, the normal everyday case, not something to dump
      // internals about.
      return const SyncNoChanges();
    }

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

    // Local is cleanly ahead of remote - same deletion-safety check as
    // pull()'s fast-forward branch, mirrored here since a local delete
    // (files removed on this device, then committed above) pushed up
    // silently wipes them on every other device too, with no conflict
    // to flag it.
    if (!p.confirmed) {
      final newLocalOid = repo.head.target;
      final counts = _diffFileCounts(repo, remoteOid, newLocalOid);
      if (_isLargeDeletion(counts)) {
        return SyncNeedsConfirmation(
          addedFiles: counts.added,
          removedFiles: counts.removed,
          modifiedFiles: counts.modified,
        );
      }
    }

    final err = _pushWithRetry(repo, remote, callbacks, p.branch);
    if (err != null) return SyncFailed(err.error, debugDetail: err.detail);
    return SyncOk(committed
        ? 'Pushed as "${p.commitMessage}".'
        : 'Uploaded notes to desktop.');
  });
}

/// Opens (or, if missing, freshly clones into) the vault's repo, runs
/// [op], and always frees the repo handle afterward. Shared by both
/// pull and push so the open/recover/close bracket lives in one place.
Future<SyncResult> _withRepo(
  _SyncParams p,
  SyncResult Function(
          git.Repository repo, git.Remote remote, git.Callbacks callbacks)
      op,
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
  //
  // 2026-08-20: "make sure I don't lose data" - this recovery path used
  // to go straight to a hard reset onto the remote, unconditionally
  // overwriting anything already sitting in the vault folder. A missing
  // .git happens both on a genuinely fresh vault (nothing to lose) AND
  // after a fresh app reinstall (the routine case above), where the
  // folder can already hold real phone-side edits that were never
  // synced before the reinstall - those would be silently clobbered by
  // the hard reset below with no commit ever made for them. Not fixed
  // by merging instead of resetting: the freshly-initted local repo and
  // the remote share no common commit ancestor (git2dart's merge
  // machinery expects one), so that path isn't safe to rely on either.
  // Backing up first means the worst case is an extra folder to review,
  // never a silent loss.
  if (!await Directory('${p.vaultPath}/.git').exists()) {
    try {
      final backedUp = await backupVaultIfNotEmpty(p.vaultPath);
      final repo = git.Repository.init(
        path: p.vaultPath,
        initialHead: p.branch,
        originUrl: p.remoteUrl,
      );
      try {
        final remote = git.Remote.lookup(repo: repo, name: 'origin');
        // 2026-08-30: same real bug/fix as _pullInIsolate/_pushInIsolate
        // above - a fresh/empty remote has no branches until pushed to,
        // so the unconditional fetch+lookup threw here too. An empty
        // remote here means there's nothing to recover FROM yet - the
        // freshly re-initted local repo (above) is already correct as-is.
        final remoteRefs = remote.ls(callbacks: callbacks);
        final hasRemoteBranch =
            remoteRefs.any((r) => r.name == 'refs/heads/${p.branch}');
        if (hasRemoteBranch) {
          remote.fetch(callbacks: callbacks);
          final remoteBranch = git.Branch.lookup(
            repo: repo,
            name: 'origin/${p.branch}',
            type: git.GitBranch.remote,
          );
          repo.reset(oid: remoteBranch.target, resetType: git.GitReset.hard);
        }
      } finally {
        repo.free();
      }
      return SyncOk(backedUp
          ? 'Downloaded your notes (existing phone content backed up next to the vault first).'
          : 'Downloaded your notes.');
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
      if (repo.index.hasConflicts) {
        String? otherLabel, otherTime;
        try {
          final mergeHeadOid =
              git.Reference.lookup(repo: repo, name: 'MERGE_HEAD').target;
          final other = labelForCommit(repo, mergeHeadOid);
          otherLabel = other.label;
          otherTime = other.time.isEmpty ? null : other.time;
        } catch (_) {
          // No MERGE_HEAD to read a label from - repair still runs, just
          // falls back to a generic label.
        }
        repairAllConflictsOnDisk(p.vaultPath,
            otherLabel: otherLabel ?? 'other device', otherTime: otherTime);
        // 2026-08-27: real gap found - repairAllConflictsOnDisk (.md
        // only) was the ONLY conflict handling that ever ran here.
        // Anything else conflicted (images/PDFs in an existing vault,
        // or any file at all in a Tier 0 generic-sync repo) fell
        // straight through to finishMergeCommit below with whatever
        // libgit2's default merge left on disk - no detection, no
        // backup, no user visibility. See repairBinaryConflictsOnDisk's
        // own doc for the fix.
        repairBinaryConflictsOnDisk(repo, p.vaultPath,
            otherLabel: otherLabel ?? 'other device');
      }
      finishMergeCommit(repo, p.deviceName);
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
///
/// 2026-08-14: was gated on `repo.status.isEmpty` first, skipping
/// staging entirely when status reported clean. Real-device testing
/// found status reporting empty (statusEntries=0) even with a brand
/// new untracked file confirmed present on disk via a raw filesystem
/// listing - a real gap somewhere in git2dart 0.5.4's status binding
/// on iOS, not a wrong-path issue (confirmed same result against the
/// verified-correct vault folder). Always stages now and compares the
/// resulting tree's oid against HEAD's tree oid instead - a tree-hash
/// comparison is unambiguous and doesn't depend on the status API at
/// all, so it can't be wrong the same way.
bool commitDirtyTree(git.Repository repo, String message, String deviceName) {
  final headOid = repo.head.target;
  final parent = git.Commit.lookup(repo: repo, oid: headOid);
  final tree = _stageAndWriteTree(repo);
  if (tree.oid == parent.tree.oid) return false;
  final signature = _signatureFor(deviceName);
  git.Commit.create(
    repo: repo,
    updateRef: 'HEAD',
    author: signature,
    committer: signature,
    message: message,
    tree: tree,
    parents: [parent],
  );
  return true;
}

/// Creates the very first commit in a genuinely fresh repo (Repository
/// .init, zero commits ever made - a brand-new phone folder against a
/// brand-new empty bare repo). commitDirtyTree can't do this: its first
/// line unconditionally reads repo.head.target to find a parent commit
/// to diff the working tree against, which doesn't exist either on a
/// repo with no commit history at all - same 'reference not found'
/// error this exists to actually fix, not just relocate. 2026-08-30:
/// real device bug - this exact gap is why an existing, already-linked
/// folder synced fine but a genuinely new one kept failing the same way
/// even after git_service.dart's own remote.ls() guard.
void createInitialCommit(
    git.Repository repo, String message, String deviceName) {
  final tree = _stageAndWriteTree(repo);
  final signature = _signatureFor(deviceName);
  git.Commit.create(
    repo: repo,
    updateRef: 'HEAD',
    author: signature,
    committer: signature,
    message: message,
    tree: tree,
    parents: [],
  );
}

/// Completes an in-progress merge (from Merge.commit) by staging
/// whatever is in the working directory now (post-repair) and creating
/// the merge commit with both parents.
void finishMergeCommit(git.Repository repo, String deviceName,
    {String? message}) {
  final localOid = repo.head.target;
  final git.Oid remoteOid;
  try {
    remoteOid = git.Reference.lookup(repo: repo, name: 'MERGE_HEAD').target;
  } catch (_) {
    return; // nothing to finish - not actually mid-merge
  }

  final localCommit = git.Commit.lookup(repo: repo, oid: localOid);
  final remoteCommit = git.Commit.lookup(repo: repo, oid: remoteOid);
  final tree = _stageAndWriteTree(repo);
  final signature = _signatureFor(deviceName);

  git.Commit.create(
    repo: repo,
    updateRef: 'HEAD',
    author: signature,
    committer: signature,
    message:
        message ?? 'Merge conflicts (both sides kept) ${backupTimestamp()}',
    tree: tree,
    parents: [localCommit, remoteCommit],
  );
}

/// File-path diff between two commits, old -> new. Paths, not just
/// counts, so a confirmation dialog can offer a drill-down into exactly
/// which files, not just how many.
({List<String> added, List<String> removed, List<String> modified})
    _diffFileCounts(git.Repository repo, git.Oid oldOid, git.Oid newOid) {
  final oldTree = git.Commit.lookup(repo: repo, oid: oldOid).tree;
  final newTree = git.Commit.lookup(repo: repo, oid: newOid).tree;
  final diff =
      git.Diff.treeToTree(repo: repo, oldTree: oldTree, newTree: newTree);
  final added = <String>[], removed = <String>[], modified = <String>[];
  for (final delta in diff.deltas) {
    switch (delta.status) {
      case git.GitDelta.added:
        added.add(delta.newFile.path);
      case git.GitDelta.deleted:
        removed.add(delta.oldFile.path);
      case git.GitDelta.modified:
        modified.add(delta.newFile.path);
      default:
        break;
    }
  }
  return (added: added, removed: removed, modified: modified);
}

/// Threshold for "large chunk of existing content" - the real fear this
/// guards against is bulk/accidental emptying (a whole folder or vault
/// gone missing), not the ordinary one-note-deleted case, so this only
/// trips on a handful or more of files disappearing at once.
bool _isLargeDeletion(
        ({
          List<String> added,
          List<String> removed,
          List<String> modified
        }) counts) =>
    counts.removed.length >= 3;

git.Tree _stageAndWriteTree(git.Repository repo) {
  final index = repo.index;
  index.addAll(['*']);
  index.write();
  final treeOid = index.writeTree(repo);
  return git.Tree.lookup(repo: repo, oid: treeOid);
}

// 2026-08-18: was a single fixed "Localsync" identity for every device -
// harmless for the sync itself (git doesn't care who authored what),
// but meant a conflict could never say who made the conflicting change,
// only when. Falls back to "Localsync" if the user hasn't set a device
// name yet (kebab menu -> Device name), same as before for anyone who
// never touches the setting.
git.Signature _signatureFor(String deviceName) => git.Signature.create(
    name: deviceName.trim().isEmpty ? 'Localsync' : deviceName.trim(),
    email: 'localsync@device.local');

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
        repo: repo,
        name: 'origin/$branch',
        type: git.GitBranch.remote,
      );
      final analysis =
          git.Merge.analysis(repo: repo, theirHead: remoteBranch.target);
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

// ── Conflict repair — ports /home/rapi5/Documents/Scripts/repair_conflicts.py's
//    real strategy (not the earlier trimmed-down version this file had),
//    just triggered after git2dart's Merge.commit instead of `git merge`.
//    Operates on working-directory files as plain text, not git's index/
//    tree objects, so nothing here needed the low-level conflict API.
//
//    2026-08-21: "no need to reinvent the wheel, I have the desktop git
//    bare sync script synco, use that if you need to" - the previous
//    port here always created a conflict callout for every marker, with
//    no deduping and no Kanban handling. The real script is smarter:
//    identical (whitespace-normalized) sides collapse to just `ours`,
//    non-overlapping additive changes from both sides are auto-appended
//    with no callout at all (two devices adding different new lines
//    isn't a real conflict), Kanban board files (kanban-plugin:
//    frontmatter) get inline %% CONFLICT-OTHER %% comments instead of a
//    blockquote callout (which doesn't render inside Kanban cards), and
//    the callout names which device/when the other version came from
//    instead of a generic label. Ported line-for-line, not reinvented. ──

// 2026-08-19: the pure string-transform logic (regexes, dedupe, the
// nested-conflict flatten fix) moved to conflict_repair.dart so it can
// be unit-tested without dart:io/git2dart/Flutter - see
// test/conflict_repair_test.dart. Only the disk-walking wrapper stays
// here.
//
// 2026-08-19, later the same night: now returns how many files came
// out of repair with a real, still-unresolved SYNC CONFLICT callout -
// not just how many were touched, since repairConflictMarkers can
// auto-merge a conflict cleanly with no callout left at all (identical
// sides, or a clean non-overlapping append). This is what makes
// automatic navigation into the Conflicts screen possible: the pull
// result can now honestly say how many files actually need a decision
// instead of a generic "merged" message that looks identical whether
// nothing happened or three files just went into conflict - see this
// session's own mermaid flowchart of the flow this replaces.
int repairAllConflictsOnDisk(String path,
    {String otherLabel = 'other device', String? otherTime}) {
  var unresolvedCount = 0;
  final dir = Directory(path);
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.md')) continue;
    try {
      final content = entity.readAsStringSync();
      if (!content.contains('<<<<<<< ')) continue;
      final repaired = repairConflictMarkers(content,
          otherLabel: otherLabel, otherTime: otherTime);
      entity.writeAsStringSync(repaired);
      if (repaired.contains('SYNC CONFLICT') ||
          repaired.contains('CONFLICT-OTHER')) {
        unresolvedCount++;
      }
    } catch (_) {
      // Skip unreadable files
    }
  }
  return unresolvedCount;
}

/// Resolves every remaining index conflict repairAllConflictsOnDisk
/// didn't touch (anything not ending in .md - images, PDFs, or any file
/// at all in a Tier 0 generic-sync repo, which has no markdown to begin
/// with). A binary/generic file can't be text-merged or wrapped in a
/// callout the way conflict_scanner.dart does for markdown, so the
/// safety net works at the whole-file level instead: both sides get
/// backed up as real files (not a markdown note - content may not be
/// text at all), "ours" is kept as the resolved result (deterministic,
/// not whatever libgit2's own default merge happened to leave on disk),
/// and the conflict is cleared from the index so it doesn't block the
/// merge commit. Nothing is silently dropped - same convention
/// conflict_scanner.dart already uses for text, applied here because
/// this repair pass is the only place a genuinely unresolvable-by-text
/// conflict is guaranteed to be seen before it gets committed.
///
/// 2026-08-27: real gap found - before this, any conflict here fell
/// straight through to finishMergeCommit with no detection, no backup,
/// and no user visibility at all. Picking either side as a real,
/// visible choice (like the markdown Conflicts screen offers) is real,
/// buildable follow-up work - this closes the actual safety hole first.
int repairBinaryConflictsOnDisk(
  git.Repository repo,
  String vaultPath, {
  String otherLabel = 'other device',
}) {
  var resolvedCount = 0;
  final conflicts = repo.index.conflicts;
  for (final path in conflicts.keys.toList()) {
    if (path.endsWith('.md')) continue; // handled by repairAllConflictsOnDisk
    final entry = conflicts[path]!;
    try {
      _resolveBinaryConflict(repo, vaultPath, path, entry, otherLabel);
      resolvedCount++;
    } catch (_) {
      // Leaves this one path as a real, still-unresolved index conflict
      // rather than guessing - finishMergeCommit will surface it via
      // whatever git2dart does with a genuinely unhandled conflict,
      // which is still safer than silently writing a wrong guess here.
    }
  }
  return resolvedCount;
}

void _resolveBinaryConflict(
  git.Repository repo,
  String vaultPath,
  String relPath,
  git.ConflictEntry entry,
  String otherLabel,
) {
  final backupDir =
      Directory('$vaultPath/$kLocalSyncFolderName/Conflict Backups');
  backupDir.createSync(recursive: true);
  final rawName = relPath.split('/').last;
  // Extension preserved at the very end (not just appended after the
  // whole original filename) so the backup file itself still opens in
  // whatever app handles that file type - same convention
  // vault_backup.dart's "Vault Backup <timestamp>" folder naming and
  // the markdown conflict backups already use.
  final dot = rawName.lastIndexOf('.');
  final stem = dot > 0 ? rawName.substring(0, dot) : rawName;
  final ext = dot > 0 ? rawName.substring(dot) : '';
  final ts = backupTimestamp();

  final ours = entry.our;
  final theirs = entry.their;
  String? keptBackupName, otherBackupName;

  if (ours != null) {
    final blob = git.Blob.lookup(repo: repo, oid: ours.oid);
    keptBackupName = '$stem - yours - $ts$ext';
    File('${backupDir.path}/$keptBackupName')
        .writeAsBytesSync(blob.contentBytes);
  }
  if (theirs != null) {
    final blob = git.Blob.lookup(repo: repo, oid: theirs.oid);
    otherBackupName = '$stem - $otherLabel - $ts$ext';
    File('${backupDir.path}/$otherBackupName')
        .writeAsBytesSync(blob.contentBytes);
  }

  // Logged so the Conflicts screen can offer a real choice later - see
  // binary_conflict_log.dart. Only logged when both sides genuinely
  // exist to choose between; a one-sided conflict (only added-by-them,
  // say) has nothing to swap to.
  if (keptBackupName != null && otherBackupName != null) {
    appendBinaryConflictLogEntry(
      vaultPath,
      BinaryConflictLogEntry(
        path: relPath,
        keptBackupName: keptBackupName,
        otherBackupName: otherBackupName,
        otherLabel: otherLabel,
        when: ts,
      ),
    );
  }

  // Keep "ours" as the resolved content when it exists; if only
  // "theirs" exists (e.g. they added a file we never touched), that's
  // the only real content to keep - never leave the file missing.
  final kept = ours ?? theirs;
  if (kept == null) return; // both sides deleted it - nothing to keep
  final blob = git.Blob.lookup(repo: repo, oid: kept.oid);
  File('$vaultPath/$relPath').writeAsBytesSync(blob.contentBytes);
  // Re-staging at this path clears its conflict entries (stage >0) and
  // replaces them with a single stage-0 entry - the standard libgit2
  // resolution step, same as `git add` on a manually resolved conflict.
  repo.index.add(relPath);
}

/// Mirrors synco.sh's SYNCO_OTHER_LABEL/SYNCO_OTHER_TIME - the other
/// side's device name and formatted date, used to name which
/// device/when a conflicting version came from instead of a generic
/// label.
///
/// 2026-08-18: was commit.summary (the commit MESSAGE - a typed note or,
/// for most auto-syncs, just another timestamp) - that could only ever
/// answer "when", never "who", since every device used to share one
/// fixed git identity. Now reads commit.author.name instead, which is
/// the actual device name (see _signatureFor) - "who" is finally a real
/// answer, not a second copy of "when".
({String label, String time}) labelForCommit(git.Repository repo, git.Oid oid) {
  try {
    final commit = git.Commit.lookup(repo: repo, oid: oid);
    final t = DateTime.fromMillisecondsSinceEpoch(commit.time * 1000);
    String p2(int v) => v.toString().padLeft(2, '0');
    // 2026-08-18: house timestamp convention is YYYYMMDDhhmm, no
    // separators - matches _timestamp()'s own commit-message format
    // elsewhere in this file, and the naming standard used throughout
    // the rest of the app. Was "YYYY-MM-DD hh:mm" - readable, but
    // inconsistent with everywhere else.
    final time =
        '${t.year}${p2(t.month)}${p2(t.day)}${p2(t.hour)}${p2(t.minute)}';
    return (label: commit.author.name, time: time);
  } catch (_) {
    return (label: 'other device', time: '');
  }
}

// 2026-08-19: was defaulting anything unmatched to mergeConflict - same
// misdiagnosis class fixed in git_service.dart's/pairing_controller.
// dart's _diagnose() the same day (see LinkingError.unclassifiedError).
// A real merge conflict is genuinely detected earlier via
// Merge.analysis()/index.hasConflicts, not inferred from exception
// text at all - this catch-all was only ever reachable for a
// completely different, unrecognized failure, so labeling it
// "mergeConflict" was never correct even before this fix.
LinkingError _diagnose(Object e) {
  final msg = e.toString();
  if (msg.contains('Connection refused') ||
      msg.contains('No route to host') ||
      msg.contains('failed to connect') ||
      msg.contains('timed out')) {
    return LinkingError.connectionRefused;
  }
  if (msg.contains('authentication') ||
      msg.contains('Auth') ||
      msg.contains('publickey')) {
    return LinkingError.sshAuthFailed;
  }
  if (msg.contains('does not appear to be a git repository') ||
      msg.contains('repository not found')) {
    return LinkingError.bareRepoNotFound;
  }
  if (msg.contains('non-fast-forward') || msg.contains('fast-forward')) {
    return LinkingError.cannotFastForward;
  }
  if (msg.contains('index is locked') || msg.contains('index.lock')) {
    return LinkingError.indexLocked;
  }
  return LinkingError.unclassifiedError;
}
