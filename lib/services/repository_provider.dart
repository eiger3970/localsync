// services/repository_provider.dart

import 'package:flutter/foundation.dart';
import '../features/linking/linking_state.dart';
import '../models/repository.dart';
import '../models/commit_template.dart';
import 'database_service.dart';
import 'device_name.dart';
import 'sync_service.dart';
import 'ssh_key_paths.dart';

class RepositoryProvider extends ChangeNotifier {
  final _db = DatabaseService();

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

  void selectRepo(int id) {
    _selectedRepoId = id;
    notifyListeners();
  }

  // ── Device name ─────────────────────────────────────────────────────────────
  // Used as the git commit author for this device - see sync_service.dart's
  // _signatureFor. Exposed here (not straight to DatabaseService from the
  // UI) so every read/write of app state goes through one place.
  Future<String?> getDeviceName() => _db.getDeviceName();
  Future<void> setDeviceName(String name) => _db.setDeviceName(name);

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
    _loading = false;
    notifyListeners();
    // 2026-08-15: was syncRepository() (the old do-everything sync) -
    // launch behavior is "bring in whatever's new", i.e. a pull, never
    // a push of local changes the user hasn't reviewed yet.
    for (final repo in _repos.where((r) => r.autoSync)) {
      final result = await pullRepository(repo.id!);
      if (result case SyncOkWithConflicts()) {
        _pendingConflictRepoId = repo.id;
        notifyListeners();
      }
    }
  }

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
  Future<SyncResult?> pullRepository(int id, {bool confirmed = false}) =>
      _run(id, (service) => service.pull(confirmed: confirmed));

  Future<SyncResult?> pushRepository(int id,
          {String? commitMessage, bool confirmed = false}) =>
      _run(id, (service) =>
          service.push(commitMessage: commitMessage, confirmed: confirmed));

  Future<SyncResult?> _run(
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
          );
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
              );
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
              );
            // 2026-08-18: not an error and not a completed sync - the
            // caller (a confirmation dialog) decides what happens next,
            // so this just drops back to idle with nothing recorded.
            case SyncNeedsConfirmation():
              _repos[i] = _repos[i].copyWith(
                status:    SyncStatus.idle,
                syncPhase: SyncPhase.idle,
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
      );
      notifyListeners();
      await _db.updateRepository(_repos[i]);
      return SyncFailed(LinkingError.mergeConflict, debugDetail: e.toString());
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
    _repos[idx] = _repos[idx].copyWith(status: status, syncPhase: phase);
    notifyListeners();
  }
}
