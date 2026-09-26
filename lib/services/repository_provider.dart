// services/repository_provider.dart

import 'desktop_schedule.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../features/linking/linking_state.dart';
import '../models/repository.dart';
import '../models/commit_template.dart';
import 'backup_reminder_service.dart';
import 'conflict_scanner.dart';
import 'demo_conflict.dart';
import 'database_service.dart';
import 'device_name.dart';
import 'sync_service.dart';
import 'sound_service.dart';
import 'ssh_key_paths.dart';
import 'vault_folder_service.dart';

class RepositoryProvider extends ChangeNotifier {
  final _db = DatabaseService();

  // 2026-09-16: bridge to AppDelegate.swift's BackupStatusChannel - the
  // widget extension can't run Dart at all, so this is the only way it
  // ever learns "a sync just succeeded". The in-app lastSync timestamp
  // above is the source of truth either way, this is purely a
  // best-effort mirror for the Home Screen widget's traffic-light
  // indicator - a failure here never blocks or fails the sync itself.
  //
  // 2026-09-17: confirmed via real-device diagnostics that this write
  // does land (readback verified), but the widget extension's own
  // process still can't see it - a non-shared App Group container under
  // the current free/sideload signing setup, not something fixable from
  // this side. Left as best-effort/silently-swallowed on purpose until
  // that's resolved - see project_synclocal_app memory's 2026-09-17
  // section for the full diagnosis.
  static const _backupStatusChannel = MethodChannel('localsync/backup_status');
  Future<void> _recordBackupTimestamp() async {
    try {
      await _backupStatusChannel.invokeMethod('recordSync');
    } catch (_) {}
  }

  List<Repository>     _repos     = [];
  List<CommitTemplate> _templates = [];
  bool                 _loading   = true;
  int?                 _selectedRepoId;

  // 2026-08-19: the auto-sync-on-launch pull below runs from the
  // constructor, before any screen exists to navigate from - it can't
  // just push a route the way home_screen.dart's manual pull handler
  // does. This is the signal HomeScreen watches instead: a repo id
  // shows up here once an auto-launch pull comes back with real
  // unresolved conflicts, HomeScreen navigates to ConflictsScreen for
  // it on the next frame and calls clearPendingConflict() so it only
  // fires once. Without this, "way too convoluted, automate it" was
  // only half fixed - a manually-tapped pull got the new navigation,
  // but the auto-sync pull that fires on every app launch (the more
  // common path for a repo with AUTO sync on) had none at all, not
  // even the old snackbar.
  int? _pendingConflictRepoId;
  int? get pendingConflictRepoId => _pendingConflictRepoId;
  void clearPendingConflict() { _pendingConflictRepoId = null; }

  // 2026-09-18: real ask, live - "can the Kebab icon change colour from
  // white to amber if a conflict exists?" A sync landing SyncOkWithConflicts
  // marks the repo id here immediately (see _runLocked below) - a fast,
  // free-to-check signal for the common case (just synced, conflicts
  // fresh). refreshConflicts() does the real, more expensive disk scan
  // (scanForConflicts) for the other case: returning from ConflictsScreen,
  // where the set above could be stale either way (fully resolved, or
  // conflicts still open because the user backed out early).
  final Set<int> _reposWithConflicts = {};
  bool hasConflicts(int repoId) => _reposWithConflicts.contains(repoId);

  // 2026-09-24: real ask, live - "Conflicts image shows white or amber
  // without having to enter conflicts?" Two gaps: nothing ran this at
  // app start (the set above starts empty, so a vault with conflicts
  // left over from last time showed white until Conflicts was opened),
  // and it scanned repo.localPath directly - on iOS the vault is another
  // app's folder, only readable through its security-scoped bookmark
  // (same as ConflictsScreen._scan), so the scan could come back empty
  // and wrongly clear amber. Now resolves the bookmark first, and on any
  // failure leaves the current colour alone rather than guessing.
  // 2026-09-26: real bug, live - "didn't update the amber to white after
  // exiting Conflicts. I had to re-enter Conflicts and exit." The rescan
  // on return raced ConflictsScreen's own last scan for the same
  // security-scoped folder and failed silently (keeps the old colour).
  // ConflictsScreen now reports every scan it completes here, so the
  // colour is already right before the user even leaves.
  void setHasConflicts(int repoId, bool has) {
    if (has == _reposWithConflicts.contains(repoId)) return;
    if (has) {
      _reposWithConflicts.add(repoId);
    } else {
      _reposWithConflicts.remove(repoId);
      unawaited(SoundService.instance.play(SoundEvent.conflictsCleared));
    }
    notifyListeners();
  }

  Future<void> refreshConflicts(int repoId) async {
    final repo = _repos.where((r) => r.id == repoId).firstOrNull;
    if (repo == null) return;
    final vf = VaultFolderService();
    String? path;
    var accessed = false;
    try {
      if (repo.vaultBookmark.isNotEmpty) {
        path = await vf.startAccessing(repo.vaultBookmark);
        accessed = path != null;
      } else {
        path = repo.localPath;
      }
      if (path == null) return;
      final entries = await scanForConflicts(path);
      if (entries.isEmpty) {
        // 2026-09-24: "all conflicts cleared" chime - only on the real
        // transition from some open conflicts to none, never on a
        // routine re-check of an already-clean vault.
        if (_reposWithConflicts.contains(repoId)) {
          unawaited(SoundService.instance.play(SoundEvent.conflictsCleared));
        }
        _reposWithConflicts.remove(repoId);
      } else {
        _reposWithConflicts.add(repoId);
      }
      notifyListeners();
    } catch (_) {
      // Best-effort - an unreadable vault keeps the last known colour.
    } finally {
      if (accessed) await vf.stopAccessing(repo.vaultBookmark);
    }
  }

  /// Runs [refreshConflicts] for every repo - at startup, so the
  /// Conflicts row is right before anything else happens.
  Future<void> refreshAllConflicts() async {
    await DemoConflict.stage(); // sets DemoConflict.triesLeft
    for (final r in List.of(_repos)) {
      if (r.id != null) await refreshConflicts(r.id!);
    }
  }

  // 2026-09-16: same pattern as _pendingConflictRepoId above - an iOS
  // Home Screen Quick Action (main.dart's QuickActions().initialize
  // callback) can fire before HomeScreen exists (cold launch) or from
  // outside any widget's BuildContext (warm launch), so there's nothing
  // to call _runAndShow on directly from there. HomeScreen watches this
  // instead and runs the real push/pull - never a raw provider call
  // that would skip _runAndShow's own confirm dialogs/SnackBar
  // feedback. Value is 'action_push' or 'action_pull' (the shortcut
  // item's own type string, set in main.dart).
  String? _pendingQuickAction;
  String? get pendingQuickAction => _pendingQuickAction;
  void setPendingQuickAction(String action) {
    _pendingQuickAction = action;
    _lastQuickActionAt = DateTime.now();
    notifyListeners();
  }

  // 2026-09-24: real regression, live - widget Push: "shows gif and
  // graphics for a second, but then black screen with top bar" reading
  // "Pushed as 202609241530. downloading notes..." - the silent
  // auto-sync's own push+pull running right behind the widget's push.
  // Same class as 2026-09-18 round 5: HomeScreen clears
  // pendingQuickAction when it starts the action, and AutoSyncOnResume's
  // "a quick action is pending, skip" guard read that flag after it was
  // already cleared. Guard on WHEN a quick action arrived instead of
  // whether the flag is still set - no ordering to get wrong.
  DateTime? _lastQuickActionAt;
  bool get quickActionJustHandled =>
      _lastQuickActionAt != null &&
      DateTime.now().difference(_lastQuickActionAt!) <
          const Duration(seconds: 15);
  void clearPendingQuickAction() { _pendingQuickAction = null; }

  // 2026-09-22: real feedback, live - widget PUSH showed its gif twice
  // with a black-screen flash in between, widget PULL crashed outright.
  // Root cause was already half-diagnosed in _inFlight's own 2026-09-18
  // comment below: a widget tap is a cold launch, and main.dart's
  // widget-action check (`localsync/widget_action` MethodChannel) is a
  // real async round trip - AutoSyncOnResume's own postFrameCallback
  // fires on the FIRST frame, before that round trip has necessarily
  // resolved, so it sees pendingQuickAction still null and launches its
  // OWN silent push+pull. The widget's real tap then runs moments later
  // once the channel resolves. _inFlight going global (2026-09-18)
  // stopped these two from racing CONCURRENTLY (the actual crash that
  // commit fixed), but never stopped them from both running, back to
  // back - exactly the redundant double-sync the double-gif symptom
  // shows, and very likely what's still stressing the pull path enough
  // to crash (no on-device crash log for this specific report yet - if
  // the crash still recurs after this fix, that log is the next thing
  // needed, not another guess).
  //
  // This future resolves once that specific async check has settled
  // (action found or not) - AutoSyncOnResume awaits it before deciding
  // whether to run its own auto-sync at cold launch, so it never acts
  // on a stale "nothing pending yet" read again.
  final Completer<void> _pendingActionCheckDone = Completer<void>();
  Future<void> get pendingActionCheckDone => _pendingActionCheckDone.future;
  void markPendingActionCheckDone() {
    if (!_pendingActionCheckDone.isCompleted) _pendingActionCheckDone.complete();
  }

  List<Repository>     get repos     => _repos;
  List<CommitTemplate> get templates => _templates;
  bool                 get loading   => _loading;

  // 2026-08-20: "Multi repo needed on app" - every screen action used
  // to silently assume repos.first, so a second linked vault was real
  // in the database but completely unreachable in the UI. This is now
  // the one thing pull/push/commit/toggle-auto/remove all target -
  // falls back to the first repo if nothing's been explicitly picked
  // yet, or if the previously-selected one was just removed (no repo
  // in _repos still has _selectedRepoId, so the fallback kicks in on
  // its own - no explicit reset needed in removeRepository below).
  Repository? get selectedRepo {
    if (_repos.isEmpty) return null;
    return _repos.firstWhere((r) => r.id == _selectedRepoId,
        orElse: () => _repos.first);
  }

  // 2026-09-25: Ken pushed the wrong folder twice - after an update the
  // app fell back to the first folder. The chosen folder is now remembered
  // on this phone across restarts and updates.
  static const _kSelectedRepoKey = 'selected_repo_id';
  void selectRepo(int id) {
    _selectedRepoId = id;
    notifyListeners();
    SharedPreferences.getInstance()
        .then((p) => p.setInt(_kSelectedRepoKey, id))
        .catchError((_) => true);
  }

  // ── Device name ─────────────────────────────────────────────────────────────
  // Used as the git commit author for this device - see sync_service.dart's
  // _signatureFor. Exposed here (not straight to DatabaseService from the
  // UI) so every read/write of app state goes through one place.
  Future<String?> getDeviceName() => _db.getDeviceName();
  Future<void> setDeviceName(String name) => _db.setDeviceName(name);

  // ── Desktop username override ───────────────────────────────────────────────
  // See database_service.dart's getDesktopUser/setDesktopUser - was
  // hardcoded to this developer's own desktop login with no override at
  // all, a real blocker for any actual customer.
  Future<String?> getDesktopUser() => _db.getDesktopUser();
  Future<void> setDesktopUser(String user) => _db.setDesktopUser(user);

  // ── Desktop IP override ────────────────────────────────────────────────────
  // See database_service.dart's getDesktopIp/setDesktopIp for why this
  // exists - same one-place-for-app-state reasoning as device name above.
  Future<String?> getDesktopIp() => _db.getDesktopIp();
  Future<void> setDesktopIp(String ip) => _db.setDesktopIp(ip);

  // ── Bare repo path override ────────────────────────────────────────────────
  // See database_service.dart's getBareRepoPath/setBareRepoPath - same
  // reasoning as Desktop IP above, real multi-repo gap.
  Future<String?> getBareRepoPath() => _db.getBareRepoPath();
  Future<void> setBareRepoPath(String path) => _db.setBareRepoPath(path);

  // ── Desktop vault path override ────────────────────────────────────────────
  // See database_service.dart's getDesktopVaultPath/setDesktopVaultPath -
  // same reasoning as Bare repo path above: lets a user reconnecting to
  // an existing desktop vault set it from Settings, no manual crontab
  // edit required.
  Future<String?> getDesktopVaultPath() => _db.getDesktopVaultPath();
  Future<void> setDesktopVaultPath(String path) => _db.setDesktopVaultPath(path);
  Future<String?> getDesktopVaultPathFor(String repoPath) => _db.getDesktopVaultPathFor(repoPath);
  Future<void> setDesktopVaultPathFor(String repoPath, String path) =>
      _db.setDesktopVaultPathFor(repoPath, path);

  // ── Auto-discovery interest capture ────────────────────────────────────────
  // See database_service.dart's getAutoDiscoveryInterest/
  // setAutoDiscoveryInterest - same one-place-for-app-state reasoning.
  Future<String?> getAutoDiscoveryInterest() => _db.getAutoDiscoveryInterest();
  Future<void> setAutoDiscoveryInterest(String price) =>
      _db.setAutoDiscoveryInterest(price);

  // ── Reminder thresholds (amber/red days) ───────────────────────────────────
  // 2026-09-18: real ask, live - "the notifications and widget traffic
  // light indicator are the same timers." See database_service.dart's
  // getAmberAfterDays/getRedAfterDays/setAmberAfterDays/setRedAfterDays.
  // Setting either one does three things, not just a DB write: pushes
  // both numbers to the widget's own App Group suite (best-effort, same
  // silently-swallowed-on-this-signing-setup caveat as
  // _recordBackupTimestamp above), and reschedules whatever notification
  // is currently pending against the new red threshold right away, not
  // just on the next sync.
  Future<int?> getAmberAfterDays() => _db.getAmberAfterDays();
  Future<int?> getRedAfterDays() => _db.getRedAfterDays();

  Future<void> setAmberAfterDays(int days) async {
    await _db.setAmberAfterDays(days);
    await _pushReminderThresholds();
  }

  Future<void> setRedAfterDays(int days) async {
    await _db.setRedAfterDays(days);
    await _pushReminderThresholds();
    // 2026-09-18: scheduleReminder() no longer swallows its own errors
    // (see its own doc) - this call site still wants best-effort (a
    // failed notification reschedule shouldn't block saving the chosen
    // threshold), so it catches here instead.
    try {
      await BackupReminderService().scheduleReminder();
    } catch (_) {}
  }

  Future<void> _pushReminderThresholds() async {
    try {
      final amber = await _db.getAmberAfterDays() ?? 1;
      final red = await _db.getRedAfterDays() ?? 7;
      await _backupStatusChannel.invokeMethod('setReminderThresholds', {
        'amberAfterDays': amber,
        'redAfterDays': red,
      });
    } catch (_) {}
  }

  RepositoryProvider() { _init(); }

  Future<void> _init() async {
    // No path pre-refresh step needed anymore (2026-08-09 rework): the
    // vault folder is now the user's own Obsidian vault, resolved fresh
    // from its security-scoped bookmark inside SyncService.fullSync()
    // itself at the start of every sync - not something this provider
    // needs to precompute or cache. The old _refreshLocalPaths() existed
    // because Localsync used to own its own container path, which was
    // NOT stable across reinstalls; that whole class of problem doesn't
    // apply to a bookmark into a different app's stable storage.
    await Future.wait([_loadRepos(), _loadTemplates()]);
    try {
      _selectedRepoId ??=
          (await SharedPreferences.getInstance()).getInt(_kSelectedRepoKey);
    } catch (_) {}
    _loading = false;
    notifyListeners();
    // 2026-09-24: Conflicts row colour right from app start - see
    // refreshConflicts. Fire-and-forget: a slow scan must not hold up
    // the first frame or the auto-sync below.
    refreshAllConflicts();
    // 2026-09-22: real crash/error found live - a widget PUSH ran its
    // gif, then hit a generic sync error; widget PULL showed no gif at
    // all (just the app bar's own status text), then crashed. The
    // 2026-09-22 AutoSyncOnResume fix closed ONE redundant silent-sync
    // path, but this loop is a SEPARATE, still-ungated third one: it
    // runs unconditionally, on every cold launch, from this
    // constructor - which fires before main.dart's initState() has even
    // started (field initializers run before initState), so it was
    // never possible for it to see pendingQuickAction as anything but
    // null, no matter what the fix above did. A widget/quick-action tap
    // still queues its own real sync behind this one via the global
    // _inFlight lock (no concurrent-access crash), but this redundant
    // silent pull - with no gif, no confirm dialog, nothing the
    // 2026-09-16 "let the explicit one win" reasoning ever got applied
    // to - still runs first every time, unlike AutoSyncOnResume's
    // already-gated auto-sync. Same fix, extended here: wait for the
    // same widget-action check to settle, then skip entirely if a
    // widget/quick action turned out to be pending - the explicit one
    // handles its own repo's sync, same as it already does for
    // AutoSyncOnResume.
    await pendingActionCheckDone;
    if (_pendingQuickAction != null) return;
    // 2026-08-15: was syncRepository() (the old do-everything sync) -
    // launch behavior is "bring in whatever's new", i.e. a pull, never
    // a push of local changes the user hasn't reviewed yet.
    for (final repo in _repos.where((r) => r.autoSync)) {
      final result = await pullRepository(repo.id!);
      if (result case SyncOkWithConflicts()) {
        _pendingConflictRepoId = repo.id;
        notifyListeners();
      } else if (result case SyncFailed()) {
        // 2026-09-18: real gap found, live - "Errors when syncing
        // under the top title bar are too small to read, can you
        // move to the bottom snack bar to make larger." A manually
        // triggered push/pull already shows the failure in a real
        // 16px bottom SnackBar (home_screen.dart's _runAndShow) - this
        // auto-launch pull never did, its ONLY surface was the
        // cramped 10px app-bar text (now removed). Same pending-flag-
        // for-the-next-frame pattern as _pendingConflictRepoId above.
        _pendingAutoSyncFailure = result;
        notifyListeners();
      }
    }
  }

  SyncResult? _pendingAutoSyncFailure;
  SyncResult? get pendingAutoSyncFailure => _pendingAutoSyncFailure;
  void clearPendingAutoSyncFailure() { _pendingAutoSyncFailure = null; }

  Future<void> _loadRepos()      async { _repos     = await _db.getRepositories(); }
  Future<void> _loadTemplates()  async { _templates = await _db.getTemplates(); }

  // ── Sync ────────────────────────────────────────────────────────────────────
  // 2026-08-15: split from a single syncRepository() into real pull()/
  // push() - see sync_service.dart's header comment for why. Both route
  // through _run(), which just watches whichever SyncService stream it's
  // given and writes the resulting status/phase/error to the repo -
  // it doesn't know or care whether that stream is a pull or a push.

  // 2026-08-16: both now return the final SyncResult (was Future<void>)
  // - "Push, is this auto committing an auto timestamp... I can't see?"
  // The result carries the actual commit message used, so a caller can
  // show it (see home_screen.dart's SnackBar) instead of the action
  // being invisible once it's done.
  // 2026-08-21: real bug, live - "HOW TO FIX IT" text tells the user
  // to "Tap TRY AGAIN," but the sync-error dialog (home_screen.dart's
  // _showFullError) never had any such button, only Close - "the text
  // is dead." That copy is accurate in the linking flow (which really
  // does have a TRY AGAIN button), just wrong when the same
  // LinkingError.resolution string gets reused for an ordinary push/
  // pull failure shown through this dialog. Tracked here (in-memory
  // only, not persisted - purely which action to retry, not real
  // state) so the dialog can offer a genuine retry of the SAME action
  // that actually failed, rather than guessing or defaulting to pull.
  final Map<int, bool> _lastActionWasPush = {};
  bool lastActionWasPush(int id) => _lastActionWasPush[id] ?? false;

  Future<SyncResult?> pullRepository(int id, {bool confirmed = false}) {
    _lastActionWasPush[id] = false;
    return _run(id, (service) => service.pull(confirmed: confirmed));
  }

  Future<SyncResult?> pushRepository(int id,
      {String? commitMessage, bool confirmed = false}) {
    _lastActionWasPush[id] = true;
    return _run(id, (service) =>
        service.push(commitMessage: commitMessage, confirmed: confirmed));
  }

  // 2026-09-17: real gap found, live - "run it sooner yourself if you
  // don't want to wait" (help_wizard.dart's Desktop PUSH/PULL notes)
  // was a promise with no real button behind it. Deliberately NOT
  // routed through _run/_runLocked - that machinery tracks the LOCAL
  // repo's own sync phase/progress, but this doesn't touch local git
  // state at all, it just asks the desktop to run its own script
  // early. The desktop script already has to tolerate being invoked
  // concurrently (cron fires it every 5 minutes regardless of whether
  // a prior run finished), so no extra client-side locking added here.
  Future<SyncResult> applyDesktopScheduleNow(
      int id, DesktopSchedule schedule) async {
    final repo = _repos.firstWhere((r) => r.id == id, orElse: () => throw
        StateError('applyDesktopScheduleNow: no repo with id $id'));
    return applyDesktopSchedule(
      schedule: schedule,
      remoteHost: repo.remoteHost,
      remotePort: repo.remotePort,
      remoteUser: repo.remoteUser,
      remotePath: repo.remotePath,
      sshPrivateKeyPath: await SshKeyPaths.privateKeyPath(),
      desktopVaultPath: await _db.getDesktopVaultPathFor(repo.remotePath),
      folderName: repo.name,
    );
  }

  Future<SyncResult?> triggerDesktopSyncNow(int id) async {
    final repo = _repos.firstWhere((r) => r.id == id, orElse: () => throw
        StateError('triggerDesktopSyncNow: no repo with id $id'));
    final result = await runDesktopSyncScriptNow(
      remoteHost: repo.remoteHost,
      remotePort: repo.remotePort,
      remoteUser: repo.remoteUser,
      remotePath: repo.remotePath,
      sshPrivateKeyPath: await SshKeyPaths.privateKeyPath(),
      desktopVaultPath: await _db.getDesktopVaultPathFor(repo.remotePath),
      folderName: repo.name,
    );
    // 2026-09-18: real ask, live - "Sync timer for widgets and phone
    // notification to remind when last backed up." This path doesn't
    // go through _runLocked's own switch (see this method's own doc on
    // why), so it needs its own reschedule call on success.
    //
    // scheduleReminder() no longer swallows its own errors - catchError
    // here keeps this call site best-effort, same as before.
    if (result is SyncOk) {
      unawaited(BackupReminderService().scheduleReminder().catchError((_) {}));
    }
    return result;
  }

  // 2026-08-21: real bug found live on the real vault - a manual push
  // right after returning to the app failed with libgit2's "current
  // tip is not the first parent." Root cause: nothing serialized two
  // sync operations against the same repo - the auto-sync-on-launch
  // pull (_init() above) and a manual push the user triggered right
  // after opening the app could both spawn their own compute() isolate
  // against the exact same local .git directory at once, each reading
  // HEAD before the other's commit landed, racing the filesystem. Not
  // data loss (a rejected commit writes nothing), but a real, confusing
  // failure with no obvious cause from the user's side. Queues a new
  // call behind whatever's already running.
  //
  // 2026-09-18: real crash, from an actual on-device .ips crash log (a
  // widget-launch push, previously undiagnosed for the whole session -
  // AutoSyncOnResume fires on cold-launch-from-widget before the
  // getPendingAction method channel result comes back, since that's
  // async - so it starts its own sync while pendingQuickAction is still
  // null, then the widget's own sync starts moments later once the
  // channel resolves). The crash itself was two DartWorker threads both
  // inside git_remote_connect's SSH handshake at once, aborting deep in
  // BoringSSL (ERR_pop_to_mark / EVP_KEYMGMT's namemap) - that's
  // process-global crypto library state, not per-connection, so two
  // concurrent handshakes corrupt it regardless of whether they're even
  // the same repo id. Per-id locking (this queue was keyed by `id`
  // until now) can't protect against that. Made global instead - no two
  // sync operations ever run at once, full stop, matching what the
  // crash log actually showed was unsafe.
  Future<void>? _inFlight;

  /// 2026-09-25: runs [fn] on the selected folder's real path, inside the
  /// same one-at-a-time lock as push/pull (so a restore never overlaps a
  /// sync on the same .git) and with iOS folder access opened and closed.
  Future<T?> withRepoFolder<T>(Repository repo, T Function(String path) fn) async {
    final prior = _inFlight;
    final done = Completer<void>();
    _inFlight = done.future;
    if (prior != null) await prior.catchError((_) {});
    final folders = VaultFolderService();
    try {
      final path = kIsWeb ? repo.localPath : await folders.startAccessing(repo.vaultBookmark);
      if (path == null) return null;
      try {
        return fn(path);
      } finally {
        if (!kIsWeb) await folders.stopAccessing(repo.vaultBookmark);
      }
    } finally {
      done.complete();
      if (identical(_inFlight, done.future)) _inFlight = null;
    }
  }
  bool get isSyncing => _inFlight != null;

  Future<SyncResult?> _run(
    int id,
    Stream<SyncEvent> Function(SyncService) op,
  ) async {
    // 2026-09-25: real crash, .ips log showed THREE DartWorker threads in
    // git_remote_fetch's SSH handshake at once - the actual root cause of
    // the 09-18/09-22 crashes, not isolate teardown. _inFlight used to be
    // claimed only AFTER awaiting `prior`, so with 3+ callers queued, the
    // 2nd and 3rd both captured the same `prior`, both woke when it
    // finished, and ran together. Claiming the slot synchronously, before
    // any await, makes every caller chain behind the one before it.
    final prior = _inFlight;
    final completer = Completer<void>();
    _inFlight = completer.future;
    if (prior != null) await prior.catchError((_) {});
    try {
      return await _runLocked(id, op);
    } finally {
      // 2026-09-22: real crash, live, from an actual .ips log AGAIN -
      // two DartWorker threads both inside git_remote_connect's SSH
      // handshake at once, same BoringSSL abort as the 2026-09-18 crash
      // this lock was built to prevent. Re-audited every call site that
      // can reach git_remote_connect (AutoSyncOnResume, this
      // provider's own _init() loop, conflict_repair.dart,
      // discovery_service.dart) - all either already gated behind this
      // lock or confirmed to never touch this native library at all
      // (discovery_service.dart's probes and conflict_repair.dart are
      // both local/pure-Dart, not git2dart). No remaining Dart-level
      // bypass found.
      //
      // Leading remaining hypothesis, not yet confirmed: compute()'s
      // returned Future resolving only means the RESULT MESSAGE was
      // received from the isolate - it's not a guarantee that the
      // isolate's own native-library cleanup (libgit2/libssh2/BoringSSL,
      // all statically linked, sharing process-global state across
      // EVERY isolate regardless of Dart-level boundaries) has actually
      // finished on its own thread by that exact instant. A `_run()`
      // call arriving immediately after `_inFlight` clears could start
      // a brand new isolate's own git_remote_connect while the PREVIOUS
      // isolate's native teardown is still mid-flight - genuine
      // concurrent BoringSSL access despite the Dart-level lock being
      // textbook-correct. A short real-world grace period before
      // releasing the lock gives that teardown room to actually finish,
      // cheaply, without needing to change how the lock itself works.
      // If real crash logs still show this after this change, the
      // hypothesis above is wrong and needs revisiting, not another
      // delay tweak.
      await Future.delayed(const Duration(milliseconds: 400));
      completer.complete();
      if (identical(_inFlight, completer.future)) _inFlight = null;
    }
  }

  Future<SyncResult?> _runLocked(
    int id,
    Stream<SyncEvent> Function(SyncService) op,
  ) async {
    final idx = _repos.indexWhere((r) => r.id == id);
    if (idx == -1) return null;

    final repo    = _repos[idx];
    final savedName = await _db.getDeviceName();
    final service = SyncService.fromRepo(
      repo,
      sshPrivateKeyPath: await SshKeyPaths.privateKeyPath(),
      sshPublicKeyPath:  await SshKeyPaths.publicKeyPath(),
      deviceName: (savedName != null && savedName.trim().isNotEmpty)
          ? savedName
          : await defaultDeviceName(),
    );

    _setPhase(idx, SyncStatus.syncing, SyncPhase.detecting);

    try {
      await for (final event in op(service)) {
        final i = _repos.indexWhere((r) => r.id == id);
        if (i == -1) return null;

        if (event.phase != null) {
          _repos[i] = _repos[i].copyWith(
            status:    SyncStatus.syncing,
            syncPhase: event.phase,
            // 2026-09-09: a new phase starting means any progress
            // fraction from the previous phase (or a previous sync
            // entirely) is stale - see Repository.syncProgress's own
            // doc comment for why copyWith can't just be left to
            // default it away on its own.
            clearSyncProgress: true,
          );
          notifyListeners();
        } else if (event.progress != null) {
          // 2026-09-09: real feedback, live - "can progress be shown
          // from 0-100%." Real data from sync_service.dart's own
          // ReceivePort plumbing - see SyncEvent.progress's doc comment.
          _repos[i] = _repos[i].copyWith(syncProgress: event.progress);
          notifyListeners();
        } else if (event.result case final result?) {
          switch (result) {
            case SyncNoChanges():
            case SyncOk():
            // 2026-08-19: grouped with the other success cases, not
            // treated as an error - the merge itself succeeded and the
            // conflict is fully backed up/resolvable, this just also
            // carries a followup action. home_screen.dart's caller
            // checks for this case separately (before falling through
            // to this generic status update) to navigate straight into
            // the Conflicts screen - see SyncOkWithConflicts's own
            // comment in sync_service.dart for why this replaced the
            // old SyncConflict class.
            case SyncOkWithConflicts():
              _repos[i] = _repos[i].copyWith(
                status:    SyncStatus.ok,
                syncPhase: SyncPhase.done,
                lastSync:  DateTime.now(),
                clearSyncProgress: true,
              );
              // 2026-09-18: real bug, found live while wiring in the
              // backup reminder below - SyncNoChanges()/SyncOk() share
              // this exact body with SyncOkWithConflicts() (empty-case
              // Dart fallthrough), so this used to run unconditionally
              // for EVERY successful sync, not just ones with real
              // conflicts - marking a repo as amber-worthy (Conflicts
              // row) after any clean push/pull. Scoped to the actual
              // result type instead of the case label that happened to
              // reach here.
              if (result case SyncOkWithConflicts()) {
                _reposWithConflicts.add(id);
              } else {
                // 2026-09-24: a clean sync can also mean conflicts were
                // resolved elsewhere (e.g. on the desktop) - re-check so
                // amber clears without opening Conflicts.
                unawaited(refreshConflicts(id));
              }
              await _recordBackupTimestamp();
              // 2026-09-18: real ask, live - "Sync timer for widgets
              // and phone notification to remind when last backed up."
              // Rescheduled on every real success (including plain
              // SyncNoChanges - the user actively confirmed they're up
              // to date, that still counts) - see
              // backup_reminder_service.dart's own doc for the full
              // reasoning. scheduleReminder() no longer swallows its own
              // errors - catchError here keeps this call site
              // best-effort, same as before.
              unawaited(
                  BackupReminderService().scheduleReminder().catchError((_) {}));
            // 2026-08-20: "show error in human language, how to fix it,
            // then the error code verbose details - some errors do
            // this, others don't" - these two cases used to join
            // diagnosis+resolution+debug into one pre-formatted string,
            // which is exactly why the sync-error dialog could only
            // ever show one undifferentiated block. Split into
            // Repository's three separate error fields instead, same
            // shape LinkingError already used - home_screen.dart's
            // dialog now renders all three through the same DiagCard
            // layout the setup flow uses.
            case SyncFailed(:final diagnosis, :final resolution, :final debugDetail):
              _repos[i] = _repos[i].copyWith(
                status:    SyncStatus.error,
                syncPhase: SyncPhase.idle,
                lastError:           diagnosis,
                lastErrorResolution: resolution,
                lastErrorDebug:      debugDetail,
                clearSyncProgress: true,
              );
            // 2026-08-18: not an error and not a completed sync - the
            // caller (a confirmation dialog) decides what happens next,
            // so this just drops back to idle with nothing recorded.
            case SyncNeedsConfirmation():
              _repos[i] = _repos[i].copyWith(
                status:    SyncStatus.idle,
                syncPhase: SyncPhase.idle,
                clearSyncProgress: true,
              );
          }
          notifyListeners();
          await _db.updateRepository(_repos[i]);
          return result;
        }
      }
      return null;
    } catch (e) {
      final i = _repos.indexWhere((r) => r.id == id);
      if (i == -1) return null;
      // 2026-08-20: was a single 'Sync error: $e' string with no
      // resolution step and no way to see the raw exception separately
      // - an unexpected exception here got a worse error format than a
      // classified LinkingError did. Now the same 3-part shape as the
      // SyncFailed case above.
      _repos[i] = _repos[i].copyWith(
        status:    SyncStatus.error,
        syncPhase: SyncPhase.idle,
        lastError: 'Something went wrong during sync.',
        lastErrorResolution:
            'Try again. If this keeps happening, check your connection to your desktop.',
        lastErrorDebug: e.toString(),
        clearSyncProgress: true,
      );
      notifyListeners();
      await _db.updateRepository(_repos[i]);
      // 2026-08-21: real bug, found while cross-checking the user's own
      // sync-error research notes against every LinkingError case's
      // actual reachability - this was hardcoded to mergeConflict,
      // completely unrelated to whatever [e] actually was. Meant the
      // SnackBar (syncResultMessage(result), reads this return value)
      // and the "Sync error" dialog (reads repo.lastError, set just
      // above) could show two DIFFERENT messages for the exact same
      // failure. unclassifiedError matches what was actually persisted
      // above - same honest-fallback pattern sync_service.dart's own
      // _diagnose() already uses.
      return SyncFailed(LinkingError.unclassifiedError, debugDetail: e.toString());
    }
  }

  Future<void> toggleAutoSync(int id) async {
    final idx = _repos.indexWhere((r) => r.id == id);
    if (idx == -1) return;
    _repos[idx] = _repos[idx].copyWith(autoSync: !_repos[idx].autoSync);
    notifyListeners();
    await _db.updateRepository(_repos[idx]);
  }

  // ── CRUD ────────────────────────────────────────────────────────────────────

  Future<void> addRepository(Repository repo) async {
    final id = await _db.insertRepository(repo);
    _repos.add(repo.copyWith(id: id));
    // Whatever you just linked becomes the active one - otherwise
    // finishing setup on a second vault would silently land back on
    // whichever was already selected, with the new one only reachable
    // via the app-bar switcher.
    _selectedRepoId = id;
    notifyListeners();
    SharedPreferences.getInstance()
        .then((p) => p.setInt(_kSelectedRepoKey, id))
        .catchError((_) => true);
  }

  Future<void> removeRepository(int id) async {
    await _db.deleteRepository(id);
    _repos.removeWhere((r) => r.id == id);
    notifyListeners();
  }

  // ── Templates ───────────────────────────────────────────────────────────────

  Future<void> useTemplate(CommitTemplate template) async {
    if (template.id == null) return;
    await _db.incrementTemplate(template.id!);
    await _loadTemplates();
    notifyListeners();
  }

  Future<void> resetTemplates() async {
    await _db.resetTemplateCounts();
    await _loadTemplates();
    notifyListeners();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  void _setPhase(int idx, SyncStatus status, SyncPhase phase) {
    _repos[idx] = _repos[idx].copyWith(
      status: status,
      syncPhase: phase,
      clearSyncProgress: true,
    );
    notifyListeners();
  }
}
