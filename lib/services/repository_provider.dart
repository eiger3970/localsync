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
    await _repairMissingLocalPaths();
    _loading = false;
    notifyListeners();
    for (final repo in _repos.where((r) => r.autoSync)) {
      syncRepository(repo.id!);
    }
  }

  // Self-heals records saved before Repository.localPath existed
  // (2026-08-09) - those persisted with an empty local_path and would
  // fail every sync with bareRepoNotFound forever, with no way for the
  // user to know why or what to do about it. Since this app has exactly
  // one real local vault folder, there's nothing ambiguous to ask the
  // user about - just repair it automatically on next launch. No
  // "remove and re-add" workaround should ever be needed for this.
  Future<void> _repairMissingLocalPaths() async {
    if (kIsWeb) return;
    final broken = _repos.where((r) => r.localPath.isEmpty).toList();
    if (broken.isEmpty) return;

    final localPath = (await getApplicationDocumentsDirectory()).path;
    for (final repo in broken) {
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
