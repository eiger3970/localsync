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
import 'package:flutter/foundation.dart' show compute, debugPrint;
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
      // 2026-09-06: real feedback - "will backups fill up a user's
      // phone storage?" Best-effort, while the security-scoped bookmark
      // is still open (see this method's own history with that race) -
      // cheap and idempotent when there's nothing old to remove, so
      // running it after every pull/push (not just once per app
      // session) is fine.
      //
      // 2026-09-06, same day, real device crash: this call had no
      // protection of its own here - any exception from it (pruning's
      // own internal try/catch doesn't cover its first `dir.exists()`
      // check) propagated straight out of this whole method, discarding
      // the real, already-successful pull/push result and surfacing as
      // a crash instead of the sync just completing normally. "Best-
      // effort, never affects the sync's own result" was the intent
      // from the start - this is what actually makes that true.
      try {
        await pruneOldConflictBackups(resolvedPath);
      } catch (_) {
        // Never let a cleanup failure discard a real, already-succeeded
        // sync result.
      }
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
    if (!hasRemoteBranch) return const SyncNoChanges();
    final liveServerOid =
        remoteRefs.firstWhere((r) => r.name == 'refs/heads/${p.branch}').oid;
    final refspecsBefore = remote.fetchRefspecs;
    remote.fetch(callbacks: callbacks);
    final remoteBranch = git.Branch.lookup(
      repo: repo,
      name: 'origin/${p.branch}',
      type: git.GitBranch.remote,
    );
    // 2026-09-05: real device once confirmed the tracking-ref resolution
    // (Branch.lookup 'origin/main') stuck 39 commits behind the true
    // current tip, across multiple fetches - this check catches that
    // exact inconsistency (remote.ls() above is a live, always-accurate
    // server listing, confirmed separately) before anything downstream
    // trusts a stale tracking ref. Hasn't reproduced since across
    // several real pulls, so it's kept as a safety net rather than
    // removed outright - but 2026-09-06: real feedback, live, this used
    // to surface the full oid/refspec dump straight to the user's
    // screen on every ordinary pull, which is a real defect on its own
    // (this branch almost never fires - the dump doesn't belong in the
    // common path at all). Detail goes to debugPrint (recoverable from
    // device console logs if this ever needs diagnosing again), user
    // sees a short, honest message instead.
    if (liveServerOid != remoteBranch.target) {
      debugPrint('LocalSync pull: live server oid=$liveServerOid differs '
          'from tracking ref oid=${remoteBranch.target} after fetch - '
          'refspecs=$refspecsBefore');
      return const SyncOk('Pull came back inconsistent - try again.');
    }
    final localOid = repo.head.target;
    final remoteOid = remoteBranch.target;
    if (localOid == remoteOid) {
      // 2026-09-06: real device bug, found live - "nothing to sync"
      // here is correct at the git level (local's tracking ref really
      // does equal remote's), but a real incident this same day showed
      // the working tree can already be silently wrong on disk with
      // nothing left to trigger a fresh reset ever again, since git
      // itself sees no reason to touch a commit it already considers
      // current. verifyAndRepairCheckout (this branch's sibling above,
      // wired to the fast-forward reset) can never reach this state -
      // this is the other half, checking regardless of whether
      // anything just changed. See that function's own doc comment,
      // and verifyWorkingTreeMatchesHead's, for the full story.
      final result = verifyWorkingTreeMatchesHead(repo, p.vaultPath);
      if (result.diag != null) {
        return SyncOk(result.diag!);
      }
      if (result.repaired.isEmpty) return const SyncNoChanges();
      return SyncOk('${result.repaired.join(", ")} didn\'t match what was '
          'already synced - fixed automatically.');
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
      // 2026-09-06: kept silent, deliberately not surfaced - unlike the
      // push-retry reset below, this fast-forward branch only reaches
      // here when localOid==baseOid, meaning local is a strict git
      // ancestor of remote by definition. Every file this backs up is
      // just an old revision being superseded by a legitimate, expected
      // remote update - completely normal on every pull that brings
      // down any real change, not a rare/risky case. Surfacing it here
      // would mean alarming "your version was saved, just in case" on
      // essentially every ordinary sync - the opposite of the clarity
      // this is supposed to add. Still backed up (cheap insurance,
      // real if the ancestor assumption ever turns out wrong for a
      // reason not yet understood), just not narrated.
      backupFilesAboutToChange(
          repo, p.vaultPath, localOid, remoteOid, 'before pull reset');
      repo.reset(oid: remoteOid, resetType: git.GitReset.hard);
      // 2026-09-06: real device bug found live - a hard reset's own
      // checkout silently failed to actually write at least one real
      // file's new content to disk, while reporting success. See
      // verifyAndRepairCheckout's own doc comment for the full story.
      // Surfaced in the message unconditionally when it fires (unlike
      // the silent backup above) - unlike an ordinary content update,
      // this genuinely is the rare/unexpected case worth telling the
      // user about.
      final repaired = verifyAndRepairCheckout(
          repo, p.vaultPath, localOid, remoteOid);
      return SyncOk(repaired.isEmpty
          ? 'Downloaded latest notes.'
          : 'Downloaded latest notes. ${repaired.join(", ")} didn\'t '
              'update correctly the first time - fixed automatically.');
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
      // 2026-09-06: paths where mergeThreeWayLines below found the two
      // sides' changes genuinely disjoint and safely combined them with
      // no human input - see that function's own doc comment for why
      // this specific merge (unlike the real git one) can be trusted
      // without a device test first.
      final autoMergedPaths = <String>[];
      // 2026-09-05: kept as a debugPrint, not a user-visible message -
      // this traced down the 7b5c6a8/b587154 fix's own real bug at the
      // time, but 2026-09-06 real feedback confirmed dumping it straight
      // into the sync result blows up as a huge unreadable text block on
      // the home screen for what's usually just the ordinary "nothing
      // changed" case. Detail's still here for `flutter logs`/Xcode
      // console if this area ever needs diagnosing again.
      var diag = 'remoteOid=$remoteOid baseOid=$baseOid';
      try {
        final localCommit = git.Commit.lookup(repo: repo, oid: localOid);
        final parentOid = localCommit.parents.first;
        diag += ' parentOid=$parentOid';
        final locallyChanged = _diffFileCounts(repo, parentOid, localOid);
        final remoteTree = git.Commit.lookup(repo: repo, oid: remoteOid).tree;
        final parentTree = git.Commit.lookup(repo: repo, oid: parentOid).tree;
        final localTree = localCommit.tree;
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
          if (remoteEntryOid == null || remoteEntryOid == parentEntryOid) {
            continue;
          }
          // parentEntryOid == null means this path didn't exist before
          // local's own edit (both sides independently created a new
          // file with the same name) - mergeThreeWayLines needs a real
          // common-ancestor text to diff against, so this harder case
          // still goes straight to the manual fallback, unchanged from
          // before.
          if (parentEntryOid != null) {
            final localEntryOid = _lookupPathOid(repo, localTree, path);
            if (localEntryOid != null) {
              final baseBlob = git.Blob.lookup(repo: repo, oid: parentEntryOid);
              final oursBlob = git.Blob.lookup(repo: repo, oid: localEntryOid);
              final theirsBlob = git.Blob.lookup(repo: repo, oid: remoteEntryOid);
              if (!baseBlob.isBinary && !oursBlob.isBinary && !theirsBlob.isBinary) {
                final merged = mergeThreeWayLines(
                    baseBlob.content, oursBlob.content, theirsBlob.content);
                if (merged != null) {
                  // 2026-09-06: mergeThreeWayLines's own safety is "defer
                  // to a human on any real ambiguity," but it's still an
                  // LCS-based heuristic, not a proof - a wrong merge
                  // should never mean the pre-merge content is gone.
                  // Both real versions get saved here unconditionally,
                  // before the file is touched, same backup mechanism
                  // (and same recoverable-by-hand-in-Obsidian promise)
                  // the manual-combine path below already gives every
                  // other conflict - so a bad auto-merge is a "open two
                  // backup notes and fix it" problem, never a data-loss
                  // one.
                  final backupDir = Directory(
                      '${p.vaultPath}/$kLocalSyncFolderName/Conflict Backups');
                  backupDir.createSync(recursive: true);
                  final ts = backupTimestamp();
                  File('${backupDir.path}/'
                          '${_conflictBackupName(path, "before auto-merge, phone version", ts)}')
                      .writeAsStringSync(oursBlob.content);
                  File('${backupDir.path}/'
                          '${_conflictBackupName(path, "before auto-merge, desktop version", ts)}')
                      .writeAsStringSync(theirsBlob.content);
                  File('${p.vaultPath}/$path').writeAsStringSync(merged);
                  autoMergedPaths.add(path);
                  continue;
                }
              }
            }
          }
          divergedPaths.add(path);
        }
      } catch (e) {
        diag = 'exception: $e';
      }
      if (divergedPaths.isEmpty && autoMergedPaths.isEmpty) {
        debugPrint('LocalSync pull: nothing to sync - $diag');
        return const SyncNoChanges();
      }

      if (autoMergedPaths.isNotEmpty) {
        final tree = _stageAndWriteTree(repo);
        final signature = _signatureFor(p.deviceName);
        final parent = git.Commit.lookup(repo: repo, oid: localOid);
        git.Commit.create(
          repo: repo,
          updateRef: 'HEAD',
          author: signature,
          committer: signature,
          message:
              'Auto-merged desktop\'s independent changes to ${autoMergedPaths.join(", ")}',
          tree: tree,
          parents: [parent],
        );
      }

      if (divergedPaths.isEmpty) {
        return SyncOk(
            'Downloaded latest notes and automatically combined non-'
            'overlapping desktop changes to ${autoMergedPaths.join(", ")} '
            '(both original versions saved to LocalSync/Conflict Backups '
            'first, in case anything needs a second look).');
      }

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
          final backupName = _conflictBackupName(path, 'desktop version', ts);
          File('${backupDir.path}/$backupName').writeAsBytesSync(blob.contentBytes);
          savedNames.add(backupName);
        } catch (_) {
          // Leave this one path unreported rather than guess at content.
        }
      }
      final autoMergedNote = autoMergedPaths.isEmpty
          ? ''
          : ' (${autoMergedPaths.join(", ")} combined automatically, both '
              'original versions backed up too, no action needed there)';
      return SyncOk(
          'Pull stopped: ${divergedPaths.join(", ")} has different real '
          'content on the desktop that couldn\'t be safely combined '
          'automatically$autoMergedNote. Saved the desktop\'s version to '
          'LocalSync/Conflict Backups (${savedNames.join(", ")}) - please '
          'combine both by hand before syncing further.');
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
      final result =
          _pushWithRetry(repo, remote, callbacks, p.branch, p.vaultPath);
      if (result.error != null) {
        return SyncFailed(result.error!, debugDetail: result.detail);
      }
      final base = committed
          ? 'Pushed as "${p.commitMessage}".'
          : 'Uploaded notes to desktop.';
      final backupNote = result.backedUp.isEmpty
          ? ''
          : ' Desktop had changed ${result.backedUp.join(", ")} too - '
              'that version was saved to LocalSync/Conflict Backups before '
              'this push replaced it, just in case.';
      final repairNote = result.repaired.isEmpty
          ? ''
          : ' ${result.repaired.join(", ")} didn\'t update correctly the '
              'first time - fixed automatically.';
      return SyncOk('$base$backupNote$repairNote');
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

    final result =
        _pushWithRetry(repo, remote, callbacks, p.branch, p.vaultPath);
    if (result.error != null) {
      return SyncFailed(result.error!, debugDetail: result.detail);
    }
    final base = committed
        ? 'Pushed as "${p.commitMessage}".'
        : 'Uploaded notes to desktop.';
    final backupNote = result.backedUp.isEmpty
        ? ''
        : ' Desktop had changed ${result.backedUp.join(", ")} too - '
            'that version was saved to LocalSync/Conflict Backups before '
            'this push replaced it, just in case.';
    final repairNote = result.repaired.isEmpty
        ? ''
        : ' ${result.repaired.join(", ")} didn\'t update correctly the '
            'first time - fixed automatically.';
    return SyncOk('$base$backupNote$repairNote');
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

/// 2026-09-06: real device bug, found live, same day - after a hard
/// reset, one real file (a nested path with a comma in its own
/// filename, "Journal/2026/09/Sep 5th, 2026.md") kept its exact PRE-
/// reset disk content while every other file in the same reset checked
/// out correctly - confirmed by comparing the phone's raw on-disk file
/// (Files app, bypassing Obsidian entirely) against the real desktop-
/// committed content, which matched neither the old nor the new
/// version cleanly - it just never moved. libgit2/git2dart's own
/// checkout has a real, silent gap for at least this path shape (this
/// exact file already had a related, but distinct, git2dart path-
/// lookup gap - see _lookupPathOid's own doc comment - this is the
/// checkout step, not the lookup one). The app had no way to notice -
/// it trusted the reset call's own success as proof the working tree
/// actually matches, which this incident disproved.
///
/// Called right after every repo.reset(hard) in this file and
/// git_service.dart. Diffs [fromOid] against [toOid] to find what
/// SHOULD have changed on disk (same pattern as
/// backupFilesAboutToChange), then for each such path hashes the real
/// on-disk content straight from the working directory
/// (Blob.createFromWorkdir, not a String read first - avoids any
/// encoding-related false mismatch) and compares it against what the
/// target tree actually records. Any mismatch gets rewritten directly
/// from the correct blob - self-healing, not just detection. Best-
/// effort per path: one file's verify/repair failing never blocks the
/// rest, and this never throws back to the caller - a reset that
/// already succeeded must never be turned into a failure by this
/// safety net.
List<String> verifyAndRepairCheckout(git.Repository repo, String vaultPath,
    git.Oid fromOid, git.Oid toOid) {
  final repaired = <String>[];
  try {
    final fromTree = git.Commit.lookup(repo: repo, oid: fromOid).tree;
    final toTree = git.Commit.lookup(repo: repo, oid: toOid).tree;
    final diff =
        git.Diff.treeToTree(repo: repo, oldTree: fromTree, newTree: toTree);
    for (final delta in diff.deltas) {
      if (delta.status != git.GitDelta.added &&
          delta.status != git.GitDelta.modified) {
        continue;
      }
      final path = delta.newFile.path;
      try {
        final expectedOid = _lookupPathOid(repo, toTree, path);
        if (expectedOid == null) continue;
        git.Oid? actualOid;
        try {
          actualOid =
              git.Blob.createFromWorkdir(repo: repo, relativePath: path);
        } catch (_) {
          actualOid = null; // Missing on disk entirely - also needs repair.
        }
        if (actualOid == expectedOid) continue;
        final blob = git.Blob.lookup(repo: repo, oid: expectedOid);
        final file = File('$vaultPath/$path');
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(blob.contentBytes);
        repaired.add(path);
      } catch (_) {
        // Best-effort - one path failing to verify/repair shouldn't
        // block checking/fixing the rest.
      }
    }
  } catch (_) {
    // Best-effort safety net - never worth surfacing an error for, and
    // never worth turning an already-completed reset into a failure.
  }
  return repaired;
}

/// Folders never worth walking/checking - git's own metadata, and this
/// app's own backup output (which is never meant to match anything in
/// git, by design).
const _skipTopLevelDirs = {'.git', kLocalSyncFolderName};

/// 2026-09-06: real gap in verifyAndRepairCheckout above, found live the
/// same day - it only ever runs right after a fresh reset, diffing the
/// two commits involved. Once a phone's tracking ref already equals
/// remote's tip (localOid == remoteOid, "nothing to sync" - correct at
/// the git level), no reset ever fires again, so that check never gets
/// another chance to run.
///
/// First version of this used Diff.treeToWorkdir (the same native
/// operation `git status` itself uses) - real device retest, same day,
/// same file: it reported no mismatch at all for the exact path already
/// proven broken, even though the raw on-disk file (checked via Files
/// app, bypassing Obsidian and this app both) still had the old
/// content. This is now the THIRD distinct git2dart/libgit2 gap
/// confirmed on this one path shape (nested directory + a comma in the
/// filename) in a single session - after a Tree lookup gap and a
/// checkout gap, a tree-to-workdir diff gap too. No git2dart tree-
/// walking or diffing API can be trusted for this path any more, so
/// this doesn't use one: walks every real file on disk directly via
/// plain dart:io (zero git2dart tree/diff calls), and for each one
/// individually looks up its expected oid via _lookupPathOid (proven
/// correct all session - the one segment-at-a-time lookup that's never
/// failed on this path) and its actual on-disk oid via
/// Blob.createFromWorkdir (a single-path operation, not a bulk walk/
/// diff - the class of operation that's kept failing here). More
/// expensive than the diff-based version on a large vault, but
/// correctness matters more than speed for content this important, and
/// this path has now burned through every faster alternative.
({List<String> repaired, String? diag}) verifyWorkingTreeMatchesHead(
    git.Repository repo, String vaultPath) {
  final repaired = <String>[];
  // 2026-09-06: temporary diagnostic - two real fixes in a row (a
  // Diff.treeToWorkdir version, then a fully manual dart:io walk using
  // only single-path git2dart calls) still didn't catch a real,
  // confirmed mismatch on this exact file. Rather than guess a third
  // time, this traces every step for that one path specifically and
  // surfaces it directly in the result message - same technique that
  // actually found the original fetch bug at the start of this
  // session. Remove once the real cause is found.
  String? diag;
  try {
    final headOid = repo.head.target;
    final headTree = git.Commit.lookup(repo: repo, oid: headOid).tree;
    final root = Directory(vaultPath);
    var sawTargetFile = false;
    for (final entity
        in root.listSync(recursive: true, followLinks: false)) {
      final isTarget = entity.path.contains('Sep 5th');
      if (isTarget) {
        sawTargetFile = true;
        diag = 'DIAG entity.path=${entity.path} runtimeType='
            '${entity.runtimeType} headOid=$headOid vaultPath=$vaultPath';
      }
      if (entity is! File) {
        if (isTarget) diag = '$diag | not a File, skipped';
        continue;
      }
      final relPath = entity.path.substring(vaultPath.length + 1);
      if (isTarget) diag = '$diag | relPath=$relPath';
      final topLevel = relPath.split('/').first;
      if (_skipTopLevelDirs.contains(topLevel)) {
        if (isTarget) diag = '$diag | skipped as top-level $topLevel';
        continue;
      }
      try {
        final expectedOid = _lookupPathOid(repo, headTree, relPath);
        if (isTarget) diag = '$diag | expectedOid=$expectedOid';
        if (expectedOid == null) continue; // Not tracked - a real user file.
        final actualOid =
            git.Blob.createFromWorkdir(repo: repo, relativePath: relPath);
        if (isTarget) diag = '$diag | actualOid=$actualOid';
        if (actualOid == expectedOid) continue;
        final blob = git.Blob.lookup(repo: repo, oid: expectedOid);
        entity.writeAsBytesSync(blob.contentBytes);
        repaired.add(relPath);
        if (isTarget) diag = '$diag | REPAIRED';
      } catch (e) {
        if (isTarget) diag = '$diag | exception: $e';
        // Best-effort - one path failing to verify/repair shouldn't
        // block checking/fixing the rest.
      }
    }
    if (!sawTargetFile) diag = 'DIAG: target file never seen in walk';
  } catch (e) {
    diag = 'DIAG: outer exception: $e';
  }
  return (repaired: repaired, diag: diag);
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

/// Shared naming for every file this app backs up into LocalSync/
/// Conflict Backups, whichever code path is doing the backing up - one
/// format so a folder full of these always reads the same way.
String _conflictBackupName(String path, String label, String ts) {
  final rawName = path.split('/').last;
  final dot = rawName.lastIndexOf('.');
  final stem = dot > 0 ? rawName.substring(0, dot) : rawName;
  final ext = dot > 0 ? rawName.substring(dot) : '';
  return '$stem - $label - $ts$ext';
}

/// 2026-09-06: real defense-in-depth, not itself an admission the reset
/// logic at each call site is wrong - every hard reset in this app
/// already reasons its way to "local has nothing unique here" before
/// calling this (see each site's own comment: commitDirtyTree already
/// ran, or the merge-base check already confirmed local is a strict
/// ancestor). But a real incident the same day showed content going
/// missing with none of those git-level assumptions actually violated
/// as far as this app's own history could tell - the leading theory is
/// Obsidian's own file cache silently overwriting what LocalSync just
/// wrote to disk, entirely outside git's view, which no amount of
/// correct git reasoning here can see coming. Backing up whatever a
/// reset is about to discard needs none of those assumptions to hold:
/// diffs [fromOid] against [toOid] and saves fromOid's own committed
/// version of every file that's about to change or disappear, cheap
/// (only the files actually changing, never the whole vault) and
/// always real - a permanent, Obsidian-visible recovery copy sitting
/// in Conflict Backups regardless of what actually caused the reset to
/// be needed.
///
/// 2026-09-06: returns the backed-up file names instead of nothing -
/// real feedback, "how would a user find their lost content, this
/// needs automation, no eyeballing." A silent backup a user has to
/// stumble on by manually browsing a folder fails that bar just as
/// badly as no backup at all. Every call site below folds this into
/// its own result message, so the moment a reset actually discards
/// something, the sync result itself says so and names the file - nothing
/// to go looking for.
List<String> backupFilesAboutToChange(git.Repository repo, String vaultPath,
    git.Oid fromOid, git.Oid toOid, String label) {
  final List<String> atRisk;
  final git.Tree fromTree;
  try {
    fromTree = git.Commit.lookup(repo: repo, oid: fromOid).tree;
    final toTree = git.Commit.lookup(repo: repo, oid: toOid).tree;
    final diff =
        git.Diff.treeToTree(repo: repo, oldTree: fromTree, newTree: toTree);
    atRisk = [
      for (final delta in diff.deltas)
        if (delta.status == git.GitDelta.deleted ||
            delta.status == git.GitDelta.modified)
          delta.oldFile.path
    ];
  } catch (_) {
    // Best-effort safety net - never block the reset itself over a
    // failure to compute what it's about to discard.
    return const [];
  }
  if (atRisk.isEmpty) return const [];
  final backupDir =
      Directory('$vaultPath/$kLocalSyncFolderName/Conflict Backups');
  backupDir.createSync(recursive: true);
  final ts = backupTimestamp();
  final savedNames = <String>[];
  for (final path in atRisk) {
    try {
      final oid = _lookupPathOid(repo, fromTree, path);
      if (oid == null) continue;
      final blob = git.Blob.lookup(repo: repo, oid: oid);
      final backupName = _conflictBackupName(path, label, ts);
      File('${backupDir.path}/$backupName').writeAsBytesSync(blob.contentBytes);
      savedNames.add(backupName);
    } catch (_) {
      // Leave this one path unreported rather than let it block the
      // others or the reset itself.
    }
  }
  return savedNames;
}

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
///
/// 2026-09-06: always returns a real record now instead of null-on-
/// success - `backedUp` needs a way out even when there's no error, so
/// callers can actually tell the user when the retry's reset discarded
/// something, instead of that only ever being knowable by browsing
/// LocalSync/Conflict Backups unprompted.
({LinkingError? error, String? detail, List<String> backedUp, List<String> repaired})
    _pushWithRetry(
  git.Repository repo,
  git.Remote remote,
  git.Callbacks callbacks,
  String branch,
  String vaultPath,
) {
  try {
    remote.push(
      refspecs: ['refs/heads/$branch:refs/heads/$branch'],
      callbacks: callbacks,
    );
    return (
      error: null,
      detail: null,
      backedUp: const [],
      repaired: const []
    );
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
        return (
          error: LinkingError.cannotFastForward,
          detail: e.toString(),
          backedUp: const [],
          repaired: const []
        );
      }
      // 2026-09-06: this specific reset is the least airtight of the
      // three in this file - it fires because a push was REJECTED,
      // meaning local believed it had something real to push a moment
      // ago, not because local was known to have nothing unique from
      // the start (contrast the plain pull fast-forward above, which
      // never had anything to push in the first place). Real backup,
      // not just a defensive comment, given that gap - and, unlike the
      // fast-forward pull case, worth actually telling the user about
      // (see this function's own doc comment).
      final priorOid = repo.head.target;
      final backedUp = backupFilesAboutToChange(
          repo, vaultPath, priorOid, remoteBranch.target,
          'before push-retry reset');
      repo.reset(oid: remoteBranch.target, resetType: git.GitReset.hard);
      final repaired = verifyAndRepairCheckout(
          repo, vaultPath, priorOid, remoteBranch.target);
      remote.push(
        refspecs: ['refs/heads/$branch:refs/heads/$branch'],
        callbacks: callbacks,
      );
      return (
        error: null,
        detail: null,
        backedUp: backedUp,
        repaired: repaired
      );
    } catch (e2) {
      return (
        error: _diagnose(e2),
        detail: e2.toString(),
        backedUp: const [],
        repaired: const []
      );
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
