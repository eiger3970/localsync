// services/database_service.dart
// Web: in-memory (for UI preview). Mobile: sqflite (Phase 2).

import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/repository.dart';
import '../models/commit_template.dart';

class DatabaseService {
  // ── In-memory store (web) ──────────────────────────────────────────────────
  static final List<Repository>     _repos     = [
    // Demo repo so the home screen isn't empty on first web run
    Repository(
      id:                1,
      name:              'Obsidian_vault',
      remoteHost:        '172.20.10.6',
      remoteUser:        'rapi5',
      remotePath:        '/home/rapi5/Documents/Git_bare_repo/Md_files_bare.git',
      obsidianVaultPath: 'On My iPhone/Obsidian/Obsidian_phone_vault',
      autoSync:          true,
      status:            SyncStatus.ok,
      lastSync:          DateTime.now().subtract(const Duration(minutes: 4)),
      fileCount:         312,
    ),
  ];
  static final List<CommitTemplate> _templates = List.from(kDefaultTemplates
      .asMap()
      .entries
      .map((e) => CommitTemplate(
            id:      e.key + 1,
            label:   e.value.label,
            pattern: e.value.pattern,
          ))
      .toList());
  static int _nextId = 2;

  // ── Repositories ────────────────────────────────────────────────────────────

  Future<List<Repository>> getRepositories() async {
    if (kIsWeb) return List.from(_repos);
    return _sqfliteGetRepositories();
  }

  Future<int> insertRepository(Repository repo) async {
    if (kIsWeb) {
      final id = _nextId++;
      _repos.add(repo.copyWith(id: id));
      return id;
    }
    return _sqfliteInsertRepository(repo);
  }

  Future<void> updateRepository(Repository repo) async {
    if (kIsWeb) {
      final idx = _repos.indexWhere((r) => r.id == repo.id);
      if (idx != -1) _repos[idx] = repo;
      return;
    }
    await _sqfliteUpdateRepository(repo);
  }

  Future<void> deleteRepository(int id) async {
    if (kIsWeb) {
      _repos.removeWhere((r) => r.id == id);
      return;
    }
    await _sqfliteDeleteRepository(id);
  }

  // ── Templates ───────────────────────────────────────────────────────────────

  Future<List<CommitTemplate>> getTemplates() async {
    if (kIsWeb) {
      final all = List<CommitTemplate>.from(_templates);
      all.sort((a, b) {
        if (a.useCount != b.useCount) return b.useCount.compareTo(a.useCount);
        return a.label.compareTo(b.label);
      });
      return all;
    }
    return _sqfliteGetTemplates();
  }

  Future<void> incrementTemplate(int id) async {
    if (kIsWeb) {
      final idx = _templates.indexWhere((t) => t.id == id);
      if (idx != -1) {
        _templates[idx] = _templates[idx].copyWith(
          useCount: _templates[idx].useCount + 1,
          lastUsed: DateTime.now(),
        );
      }
      return;
    }
    await _sqfliteIncrementTemplate(id);
  }

  Future<void> resetTemplateCounts() async {
    if (kIsWeb) {
      for (int i = 0; i < _templates.length; i++) {
        _templates[i] = _templates[i].copyWith(useCount: 0);
      }
      return;
    }
    await _sqfliteResetTemplateCounts();
  }

  // ── sqflite (mobile — Phase 2) ───────────────────────────────────────────────
  // These throw on web. Will be implemented with full sqflite on mobile build.

  Future<List<Repository>>     _sqfliteGetRepositories()             async => throw _mobileOnly();
  Future<int>                  _sqfliteInsertRepository(Repository r) async => throw _mobileOnly();
  Future<void>                 _sqfliteUpdateRepository(Repository r) async => throw _mobileOnly();
  Future<void>                 _sqfliteDeleteRepository(int id)       async => throw _mobileOnly();
  Future<List<CommitTemplate>> _sqfliteGetTemplates()                 async => throw _mobileOnly();
  Future<void>                 _sqfliteIncrementTemplate(int id)      async => throw _mobileOnly();
  Future<void>                 _sqfliteResetTemplateCounts()          async => throw _mobileOnly();

  UnsupportedError _mobileOnly() =>
      UnsupportedError('sqflite only available on iOS/Android');
}
