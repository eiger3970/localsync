import 'dart:convert';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:git2dart/git2dart.dart';
import '../features/linking/linking_state.dart';
import 'sync_service.dart'
    show
        commitDirtyTree,
        createInitialCommit,
        labelForCommit,
        repairAllConflictsOnDisk,
        finishMergeCommit;
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

  final String
      bareRepoPath; // Desktop: whichever bare repo is configured in main.dart's LinkingController
  final String
      localVaultPath; // Phone: Localsync's own Documents dir (see Info.plist notes in STRUCTURE.md)
  final String
      sshHost; // Desktop's current hotspot-subnet IP, re-check each session (no settings UI yet)
  final int sshPort;
  final String sshUser; // rapi5
  final String
      sshPrivateKeyPath; // On-device path to the phone's own SSH private key
  final String
      sshPublicKeyPath; // On-device path to the phone's own SSH public key
  final String sshPassphrase; // Empty string if the key has no passphrase
  // 2026-08-26: added alongside the real merge-and-repair fix below - the
  // reused finishMergeCommit/commitDirtyTree need a real commit author,
  // same as sync_service.dart's own deviceName (see repository_provider
  // .dart's getDeviceName()/defaultDeviceName() for where callers should
  // source this from).
  final String deviceName;

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
    required this.deviceName,
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

  // 2026-08-28: real feedback, live - "ain't nobody got time for that. The
  // app needs to do it all." docs/desktop-setup.md's manual `git init
  // --bare` step (a terminal command, on the desktop) was the only way a
  // fresh bare repo ever got created - this app has never automated it.
  // By the time this runs, pairing has already installed the phone's key
  // on the desktop (features/pairing/), so it has everything needed to do
  // this itself over the same SSH access instead. Idempotent and
  // non-destructive: `rev-parse --git-dir` only fails (and `git init
  // --bare` only runs) when nothing valid exists there yet - a bare repo
  // that already exists, with real history, is never touched.
  Future<void> _ensureBareRepoExists() async {
    final socket = await SSHSocket.connect(sshHost, sshPort,
        timeout: const Duration(seconds: 15));
    final privateKeyPem = await File(sshPrivateKeyPath).readAsString();
    final client = SSHClient(
      socket,
      username: sshUser,
      identities: SSHKeyPair.fromPem(
          privateKeyPem, sshPassphrase.isEmpty ? null : sshPassphrase),
    );
    try {
      // Single-quoted, with any embedded single-quote escaped - same
      // precedent as pairing_controller.dart's own remote command
      // (bareRepoPath is a Settings value the user typed, not attacker
      // input, but escaping costs nothing here either).
      final escaped = bareRepoPath.replaceAll("'", r"'\''");
      final command = "mkdir -p \"\$(dirname '$escaped')\" && "
          "(git --git-dir='$escaped' rev-parse --git-dir >/dev/null 2>&1 || "
          "git init --bare '$escaped')";
      final res = await client.runWithResult(command);
      if (res.exitCode != 0) {
        throw Exception('Could not prepare bare repo on desktop: '
            'exit ${res.exitCode}: ${String.fromCharCodes(res.stderr)}');
      }
    } finally {
      client.close();
    }
  }

  // 2026-08-30: real device feedback - "unsure about keeping in cron
  // job, this is advanced and esoteric industry secrets, not really for
  // normies... I'm still unclear on the desktop user setup." The bare
  // repo itself was already automated (above); this was the other real
  // gap - desktop/localsync_sync.sh (keeps the desktop's own working
  // copy in sync) still needed manual copy + chmod + a hand-edited
  // crontab, per docs/desktop-setup.md. Same SSH access pairing already
  // established does all of that here instead - zero terminal steps.
  // Best-effort: failure here doesn't fail setup (the bare repo and
  // pairing already succeeded, which is the real requirement) - caught
  // and swallowed by the caller, not raised as a LinkingError.
  Future<void> _ensureDesktopSyncInstalled() async {
    final socket = await SSHSocket.connect(sshHost, sshPort,
        timeout: const Duration(seconds: 15));
    final privateKeyPem = await File(sshPrivateKeyPath).readAsString();
    final client = SSHClient(
      socket,
      username: sshUser,
      identities: SSHKeyPair.fromPem(
          privateKeyPem, sshPassphrase.isEmpty ? null : sshPassphrase),
    );
    try {
      final script = await rootBundle.loadString('desktop/localsync_sync.sh');
      final scriptB64 = base64Encode(utf8.encode(script));
      final escapedRepo = bareRepoPath.replaceAll("'", r"'\''");
      // Written to ~/Documents/Scripts/ - the exact path
      // docs/desktop-setup.md already documents by hand, so a user who
      // goes looking for it (or runs it manually later) finds it where
      // the docs said it would be, automated or not.
      //
      // $HOME below is deliberately UNQUOTED/double-quoted, not single-
      // quoted - single quotes suppress shell variable expansion, which
      // would leave the literal 4 characters "$HOME" in the path
      // instead of the real home directory (a real bug caught before
      // this shipped, not guessed at).
      const remoteDir = r'$HOME/Documents/Scripts';
      const scriptPath = r'$HOME/Documents/Scripts/localsync_sync.sh';
      final installCmd = 'mkdir -p "$remoteDir" && '
          "echo '$scriptB64' | base64 -d > \"$scriptPath\" && "
          'chmod +x "$scriptPath"';
      final installRes = await client.runWithResult(installCmd);
      if (installRes.exitCode != 0) return; // best-effort, see above
      // grep -v first removes any prior localsync_sync.sh cron line
      // before re-adding - idempotent on a re-pair, never stacks
      // duplicate entries. LOCALSYNC_VAULT is left at the script's own
      // default (~/Documents/LocalSync/vault, per docs) - the desktop's
      // own working-copy location isn't something the phone's Settings
      // has ever configured; LOCALSYNC_BARE_REPO is the one value this
      // phone actually knows and needs to override.
      final cronCmd = '(crontab -l 2>/dev/null | grep -v localsync_sync.sh; '
          'echo "*/5 * * * * LOCALSYNC_BARE_REPO=\'$escapedRepo\' '
          '$scriptPath >> \$HOME/.localsync_sync.log 2>&1") | crontab -';
      await client.runWithResult(cronCmd);
    } catch (_) {
      // Best-effort convenience step - never fails the real setup over
      // this (e.g. a desktop with no cron at all, Windows via WSL
      // oddities, etc.). Manual fallback is still fully documented in
      // docs/desktop-setup.md for exactly this case.
    } finally {
      client.close();
    }
  }

  @override
  Future<StepResult> pullFromBareRepo() async {
    await _ensurePlatformInitialized();
    try {
      await _ensureBareRepoExists();
      // 2026-08-30: best-effort, every pull (not just first-ever) -
      // idempotent (see the function's own comment) and keeps the
      // desktop script current if a future app update changes it, not
      // just installed once and forgotten.
      await _ensureDesktopSyncInstalled();
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
          // 2026-08-30: real device bug - "cannot locate remote-tracking
          // branch 'origin/main'" on a brand new phone folder. A bare
          // repo fresh from `git init --bare` (prepareBareRepo above) has
          // no branches at all until something is pushed to it - fetch()
          // succeeds either way (there's just nothing to fetch), but the
          // unconditional Branch.lookup right after it threw here every
          // time, because there was genuinely no 'origin/main' to find
          // yet. remote.ls() (already used the same way in getStatus
          // below) checks what the remote actually has, without needing
          // a fetch first - an empty remote means there's nothing to
          // pull, so this repo (already correctly initialized above)
          // is ready as-is for pushToBareRepo to establish the branch.
          final remoteRefs = remote.ls(callbacks: _callbacks);
          final hasRemoteBranch =
              remoteRefs.any((r) => r.name == 'refs/heads/$defaultBranch');
          if (hasRemoteBranch) {
            remote.fetch(callbacks: _callbacks);
            final remoteBranch = Branch.lookup(
              repo: repo,
              name: 'origin/$defaultBranch',
              type: GitBranch.remote,
            );
            repo.reset(oid: remoteBranch.target, resetType: GitReset.hard);
          } else {
            // 2026-08-30: real device bug, found after the fix above -
            // "reference 'refs/heads/main' not found" (a DIFFERENT error
            // than before - a local ref this time, not the remote-
            // tracking one). Repository.init() only creates the .git
            // skeleton - it never commits the folder's actual content,
            // so a fresh repo with an empty remote had literally zero
            // commits and no real refs/heads/$defaultBranch to push.
            // pushToBareRepo (the very next step) pushes exactly that
            // ref by name - it can't push what was never committed.
            //
            // 2026-08-30, corrected - this was commitDirtyTree, which
            // does NOT work here: its own first line unconditionally
            // reads repo.head.target to find a parent commit to diff
            // against, which throws the exact same 'reference not
            // found' error on a repo with zero commits ever made - the
            // real reason an already-linked folder synced fine while a
            // genuinely new one kept failing the same way. This is the
            // real first commit, no parent to find.
            createInitialCommit(repo, 'Initial sync from phone', deviceName);
          }
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
        // 2026-08-26: real feedback, live - a real, already-used vault
        // folder (own git history from being linked before) hit
        // LinkingError.mergeConflict and stopped setup outright. This
        // whole branch now mirrors sync_service.dart's _pullInIsolate
        // (the proven day-to-day pull path, used routinely for real
        // "Merge desktop and phone" syncs) instead of a narrower,
        // fast-forward-or-fail version of the same thing:
        //  - commitDirtyTree first, so any real, uncommitted edits sitting
        //    in the vault folder become a real commit *before* anything
        //    below can touch the working tree - the old fast-forward
        //    branch's hard reset would have silently discarded those with
        //    no backup, a real data-loss risk this fixes as a side effect.
        //  - diverged history gets an actual three-way merge with
        //    conflicts repaired in place (both sides kept), not a bare
        //    failure - matching linking_state.dart's own note that
        //    ordinary conflicts are supposed to be handled automatically,
        //    not surfaced as a dead-end LinkingError.
        //
        // 2026-08-30: real device bug, still hitting after the fresh-
        // clone branch's own fix above - a RETRY against a vault folder
        // that already has local .git state, but from an earlier attempt
        // that got this far and failed before ever committing (the exact
        // bug just fixed above), has zero commits here too. Unconditional
        // commitDirtyTree throws immediately on that (its own first line
        // reads repo.head.target, same 'reference not found' cause) -
        // never even reaches the remote.ls() guard below. Checking first
        // instead of assuming a parent commit always exists.
        try {
          repo.head.target;
          commitDirtyTree(repo, 'Vault contents before linking', deviceName);
        } catch (_) {
          createInitialCommit(
              repo, 'Vault contents before linking', deviceName);
        }

        final remote = Remote.lookup(repo: repo, name: 'origin');
        // 2026-08-30: same real device bug as the fresh-clone branch
        // above, still hitting - "same error connecting to new phone
        // folder." This is the OTHER path to the same unconditional
        // Branch.lookup: a retry against a vault folder that already has
        // local .git state (e.g. an earlier attempt got this far but the
        // push step never ran) hits this branch, not the fresh-clone one
        // above - same missing guard, same fix. An empty remote means
        // there's genuinely nothing to pull; local (just committed above)
        // is already ready for pushToBareRepo to establish the branch.
        final remoteRefs = remote.ls(callbacks: _callbacks);
        final hasRemoteBranch =
            remoteRefs.any((r) => r.name == 'refs/heads/$defaultBranch');
        if (!hasRemoteBranch) {
          return const StepSuccess(message: 'Nothing to pull yet');
        }
        remote.fetch(callbacks: _callbacks);

        final remoteBranch = Branch.lookup(
          repo: repo,
          name: 'origin/$defaultBranch',
          type: GitBranch.remote,
        );
        final localOid = repo.head.target;
        final remoteOid = remoteBranch.target;
        if (localOid == remoteOid) {
          return const StepSuccess(message: 'Already up to date');
        }

        final baseOid = Merge.base(repo, localOid, remoteOid);
        if (localOid == baseOid) {
          repo.reset(oid: remoteOid, resetType: GitReset.hard);
          return const StepSuccess(message: 'Pulled (fast-forward)');
        }
        if (remoteOid == baseOid) {
          // Local (just committed above) is already ahead - nothing new
          // to bring down. Pushing it up is the next step's job.
          return const StepSuccess(message: 'Already up to date');
        }

        // Diverged - three-way merge, conflicts repaired in place (both
        // versions kept), same as every other pull in this app.
        final annotated = AnnotatedCommit.lookup(repo: repo, oid: remoteOid);
        Merge.commit(repo: repo, commit: annotated);
        var unresolvedCount = 0;
        if (repo.index.hasConflicts) {
          final other = labelForCommit(repo, remoteOid);
          unresolvedCount = repairAllConflictsOnDisk(localVaultPath,
              otherLabel: other.label,
              otherTime: other.time.isEmpty ? null : other.time);
        }
        finishMergeCommit(repo, deviceName,
            message: 'Merge desktop and phone (linking existing vault)');
        repo.stateCleanup();
        return StepSuccess(
            message: unresolvedCount > 0
                ? 'Linked - merged in your existing notes. '
                    '$unresolvedCount file${unresolvedCount == 1 ? '' : 's'} '
                    'need your review in Conflicts.'
                : 'Linked and merged in your existing notes.');
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
