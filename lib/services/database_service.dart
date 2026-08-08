// services/database_service.dart
// Web: in-memory (for UI preview). Mobile: shared_preferences, JSON-encoded lists.
//
// Not sqflite: this app stores a handful of repos and commit templates, not
// tabular data needing SQL queries/joins. shared_preferences was already a
// dependency (used elsewhere), so this adds zero new native plugins/iOS
// CocoaPods setup. Revisit only if data volume genuinely grows past what a
// JSON blob comfortably holds - not expected for "sync a few Obsidian vaults."

import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/repository.dart';
import '../models/commit_template.dart';

const _kRepositoriesKey    = 'db_repositories';
const _kTemplatesKey       = 'db_commit_templates';
const _kTemplatesSeededKey = 'db_commit_templates_seeded';

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
    return _prefsGetRepositories();
  }

  Future<int> insertRepository(Repository repo) async {
    if (kIsWeb) {
      final id = _nextId++;
      _repos.add(repo.copyWith(id: id));
      return id;
    }
    return _prefsInsertRepository(repo);
  }

  Future<void> updateRepository(Repository repo) async {
    if (kIsWeb) {
      final idx = _repos.indexWhere((r) => r.id == repo.id);
      if (idx != -1) _repos[idx] = repo;
      return;
    }
    await _prefsUpdateRepository(repo);
  }

  Future<void> deleteRepository(int id) async {
    if (kIsWeb) {
      _repos.removeWhere((r) => r.id == id);
      return;
    }
    await _prefsDeleteRepository(id);
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
    return _prefsGetTemplates();
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
    await _prefsIncrementTemplate(id);
  }

  Future<void> resetTemplateCounts() async {
    if (kIsWeb) {
      for (int i = 0; i < _templates.length; i++) {
        _templates[i] = _templates[i].copyWith(useCount: 0);
      }
      return;
    }
    await _prefsResetTemplateCounts();
  }

  // ── shared_preferences (mobile) ──────────────────────────────────────────────

  Future<List<Repository>> _prefsGetRepositories() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_kRepositoriesKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((m) => Repository.fromMap(m as Map<String, dynamic>))
        .toList();
  }

  Future<void> _prefsSaveRepositories(List<Repository> repos) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kRepositoriesKey,
      jsonEncode(repos.map((r) => r.toMap()).toList()),
    );
  }

  Future<int> _prefsInsertRepository(Repository repo) async {
    final repos  = await _prefsGetRepositories();
    final nextId = repos.isEmpty
        ? 1
        : repos.map((r) => r.id ?? 0).reduce((a, b) => a > b ? a : b) + 1;
    repos.add(repo.copyWith(id: nextId));
    await _prefsSaveRepositories(repos);
    return nextId;
  }

  Future<void> _prefsUpdateRepository(Repository repo) async {
    final repos = await _prefsGetRepositories();
    final idx   = repos.indexWhere((r) => r.id == repo.id);
    if (idx == -1) return;
    repos[idx] = repo;
    await _prefsSaveRepositories(repos);
  }

  Future<void> _prefsDeleteRepository(int id) async {
    final repos = await _prefsGetRepositories();
    repos.removeWhere((r) => r.id == id);
    await _prefsSaveRepositories(repos);
  }

  Future<List<CommitTemplate>> _prefsGetTemplates() async {
    final prefs  = await SharedPreferences.getInstance();
    final seeded = prefs.getBool(_kTemplatesSeededKey) ?? false;

    if (!seeded) {
      final seed = kDefaultTemplates
          .asMap()
          .entries
          .map((e) => CommitTemplate(
                id:      e.key + 1,
                label:   e.value.label,
                pattern: e.value.pattern,
              ))
          .toList();
      await _prefsSaveTemplates(seed);
      await prefs.setBool(_kTemplatesSeededKey, true);
    }

    final raw  = prefs.getString(_kTemplatesKey);
    final list = raw == null
        ? <CommitTemplate>[]
        : (jsonDecode(raw) as List<dynamic>)
            .map((m) => CommitTemplate.fromMap(m as Map<String, dynamic>))
            .toList();

    list.sort((a, b) {
      if (a.useCount != b.useCount) return b.useCount.compareTo(a.useCount);
      return a.label.compareTo(b.label);
    });
    return list;
  }

  Future<void> _prefsSaveTemplates(List<CommitTemplate> templates) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kTemplatesKey,
      jsonEncode(templates.map((t) => t.toMap()).toList()),
    );
  }

  Future<void> _prefsIncrementTemplate(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_kTemplatesKey);
    if (raw == null) return;
    final list = (jsonDecode(raw) as List<dynamic>)
        .map((m) => CommitTemplate.fromMap(m as Map<String, dynamic>))
        .toList();
    final idx = list.indexWhere((t) => t.id == id);
    if (idx == -1) return;
    list[idx] = list[idx].copyWith(
      useCount: list[idx].useCount + 1,
      lastUsed: DateTime.now(),
    );
    await _prefsSaveTemplates(list);
  }

  Future<void> _prefsResetTemplateCounts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_kTemplatesKey);
    if (raw == null) return;
    final list = (jsonDecode(raw) as List<dynamic>)
        .map((m) => CommitTemplate.fromMap(m as Map<String, dynamic>))
        .toList()
        .map((t) => t.copyWith(useCount: 0))
        .toList();
    await _prefsSaveTemplates(list);
  }
}
