// services/repository_provider.dart

import 'package:flutter/foundation.dart';
import '../features/linking/linking_state.dart';
import '../models/repository.dart';
import '../models/commit_template.dart';
import 'database_service.dart';
import 'sync_service.dart';
import 'ssh_key_paths.dart';

class RepositoryProvider extends ChangeNotifier {
  final _db = DatabaseService();

  List<Repository>     _repos     = [];
  List<CommitTemplate> _templates = [];
  bool                 _loading   = true;

  List<Repository>     get repos     => _repos;
  List<CommitTemplate> get templates => _templates;
  bool                 get loading   => _loading;

  RepositoryProvider() { _init(); }

  Future<void> _init() async {
    // No path pre-refresh step needed anymore (2026-08-09 rework): the
    // vault folder is now the user's own Obsidian vault, resolved fresh
    // from its security-scoped bookmark inside SyncService.fullSync()
    // itself at the start of every sync - not something this provider
    // needs to precompute or cache. The old _refreshLocalPaths() existed
    // because Synclocal used to own its own container path, which was
    // NOT stable across reinstalls; that whole class of problem doesn't
    // apply to a bookmark into a different app's stable storage.
    await Future.wait([_loadRepos(), _loadTemplates()]);
    _loading = false;
    notifyListeners();
    // 2026-08-15: was syncRepository() (the old do-everything sync) -
    // launch behavior is "bring in whatever's new", i.e. a pull, never
    // a push of local changes the user hasn't reviewed yet.
    for (final repo in _repos.where((r) => r.autoSync)) {
      pullRepository(repo.id!);
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
  Future<SyncResult?> pullRepository(int id) =>
      _run(id, (service) => service.pull());

  Future<SyncResult?> pushRepository(int id, {String? commitMessage}) =>
      _run(id, (service) => service.push(commitMessage: commitMessage));

  Future<SyncResult?> _run(
    int id,
    Stream<SyncEvent> Function(SyncService) op,
  ) async {
    final idx = _repos.indexWhere((r) => r.id == id);
    if (idx == -1) return null;

    final repo    = _repos[idx];
    final service = SyncService.fromRepo(
      repo,
      sshPrivateKeyPath: await SshKeyPaths.privateKeyPath(),
      sshPublicKeyPath:  await SshKeyPaths.publicKeyPath(),
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
              _repos[i] = _repos[i].copyWith(
                status:    SyncStatus.ok,
                syncPhase: SyncPhase.done,
                lastSync:  DateTime.now(),
                lastError: null,
              );
            case SyncConflict(:final conflictingFiles):
              _repos[i] = _repos[i].copyWith(
                status:    SyncStatus.error,
                syncPhase: SyncPhase.idle,
                lastError: 'Conflict in: $conflictingFiles\n'
                           'Edit on desktop, resolve markers, then sync again.',
              );
            case SyncFailed(:final diagnosis, :final resolution, :final debugDetail):
              _repos[i] = _repos[i].copyWith(
                status:    SyncStatus.error,
                syncPhase: SyncPhase.idle,
                lastError: debugDetail != null
                    ? '$diagnosis\n$resolution\n\nRaw error (temporary diagnostic):\n$debugDetail'
                    : '$diagnosis\n$resolution',
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
      _repos[i] = _repos[i].copyWith(
        status:    SyncStatus.error,
        syncPhase: SyncPhase.idle,
        lastError: 'Sync error: $e',
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
