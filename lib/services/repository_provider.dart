// services/repository_provider.dart

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
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
    await Future.wait([_loadRepos(), _loadTemplates()]);
    await _refreshLocalPaths();
    _loading = false;
    notifyListeners();
    for (final repo in _repos.where((r) => r.autoSync)) {
      syncRepository(repo.id!);
    }
  }

  // Refreshes every repo's localPath on every launch, unconditionally -
  // not just when empty. Originally (2026-08-09) this only repaired
  // records with an empty local_path (from before the field existed),
  // but real-device testing found the deeper problem: on iOS, the
  // app's own container path (getApplicationDocumentsDirectory()) is
  // NOT stable - it changes on every reinstall, which happens on every
  // rebuild+resideload during development. A path that was valid last
  // launch can be stale (pointing at a container that no longer
  // exists) by this launch, even though it's non-empty and "looks"
  // valid - hit exactly this as GIT_ERROR_OS "failed to make
  // directory ... Operation not permitted" (trying to write into an
  // orphaned old container). Since this app has exactly one real local
  // vault folder, there's nothing to lose by always recomputing it live
  // rather than trusting a cached value - cheap and removes an entire
  // class of stale-path bugs, not just the one where it happened to be
  // empty.
  Future<void> _refreshLocalPaths() async {
    if (kIsWeb || _repos.isEmpty) return;
    final localPath = (await getApplicationDocumentsDirectory()).path;
    for (final repo in _repos) {
      if (repo.localPath == localPath) continue;
      final idx = _repos.indexWhere((r) => r.id == repo.id);
      if (idx == -1) continue;
      _repos[idx] = _repos[idx].copyWith(localPath: localPath);
      await _db.updateRepository(_repos[idx]);
    }
  }

  Future<void> _loadRepos()      async { _repos     = await _db.getRepositories(); }
  Future<void> _loadTemplates()  async { _templates = await _db.getTemplates(); }

  // ── Sync ────────────────────────────────────────────────────────────────────

  Future<void> syncRepository(int id, {String? commitMessage}) async {
    // Defense in depth alongside _refreshLocalPaths() in _init(): always
    // use a live-computed path for the actual git call, never trust
    // whatever's cached in _repos at this point, in case sync gets
    // triggered through some path that didn't go through _init() first.
    await _refreshLocalPaths();

    final idx = _repos.indexWhere((r) => r.id == id);
    if (idx == -1) return;

    final repo    = _repos[idx];
    final service = SyncService.fromRepo(
      repo,
      sshPrivateKeyPath: await SshKeyPaths.privateKeyPath(),
      sshPublicKeyPath:  await SshKeyPaths.publicKeyPath(),
    );

    _setPhase(idx, SyncStatus.syncing, SyncPhase.detecting);

    try {
      await for (final event in service.fullSync(commitMessage: commitMessage)) {
        final i = _repos.indexWhere((r) => r.id == id);
        if (i == -1) return;

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
          return;
        }
      }
    } catch (e) {
      final i = _repos.indexWhere((r) => r.id == id);
      if (i == -1) return;
      _repos[i] = _repos[i].copyWith(
        status:    SyncStatus.error,
        syncPhase: SyncPhase.idle,
        lastError: 'Sync error: $e',
      );
      notifyListeners();
      await _db.updateRepository(_repos[i]);
    }
  }

  Future<void> commitAndPush(int id, String message) async {
    await syncRepository(id, commitMessage: message);
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
