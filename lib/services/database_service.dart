// services/database_service.dart
// Web: in-memory (for UI preview). Mobile: shared_preferences, JSON-encoded lists.
//
// Not sqflite: this app stores a handful of repos and commit templates, not
// tabular data needing SQL queries/joins. shared_preferences was already a
// dependency (used elsewhere), so this adds zero new native plugins/iOS
// CocoaPods setup. Revisit only if data volume genuinely grows past what a
// JSON blob comfortably holds - not expected for "sync a few Obsidian vaults."

import 'dart:convert';
import '../constants.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/repository.dart';
import '../models/commit_template.dart';
import 'resolved_watchlist.dart';

const _kRepositoriesKey       = 'db_repositories';
const _kTemplatesKey          = 'db_commit_templates';
const _kTemplatesSeededKey    = 'db_commit_templates_seeded';
const _kDeviceNameKey         = 'db_device_name';
const _kResolvedWatchlistKey  = 'db_resolved_watchlist';
const _kDesktopIpKey          = 'db_desktop_ip';
const _kBareRepoPathKey       = 'db_bare_repo_path';
const _kAutoDiscoveryInterestKey = 'db_auto_discovery_interest';

class DatabaseService {
  // ── In-memory store (web) ──────────────────────────────────────────────────
  static final List<Repository>     _repos     = [
    // Demo repo so the home screen isn't empty on first web run
    Repository(
      id:                1,
      name:              '${kGenericAppLabel}_$kContainerName',
      remoteHost:        '172.20.10.11',
      remoteUser:        'rapi5',
      remotePath:        '/home/rapi5/Documents/Git/pi5-obsidian/Git_bare_repo/localsync.git',
      localPath:         '/web-demo-not-a-real-path',
      obsidianVaultPath: 'On My iPhone/$kNoteAppName/Localsync',
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

  // ── Device name ─────────────────────────────────────────────────────────────
  // 2026-08-18: used as the git commit author instead of the old fixed
  // "Localsync" identity (see sync_service.dart's _signatureFor) so a
  // sync conflict can say who made a change, not just when. A single
  // string, not per-web-in-memory-demo like repos/templates above -
  // shared_preferences already handles web fine for a plain value.
  static String? _webDeviceName;

  Future<String?> getDeviceName() async {
    if (kIsWeb) return _webDeviceName;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kDeviceNameKey);
  }

  Future<void> setDeviceName(String name) async {
    if (kIsWeb) {
      _webDeviceName = name;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDeviceNameKey, name);
  }

  // ── Desktop IP override ────────────────────────────────────────────────────
  // 2026-08-20: real user feedback, live - the desktop's IP was a build-
  // time constant in main.dart, meaning any network change (USB tether
  // vs hotspot vs a DHCP reassignment - all three have actually happened
  // across this project's sessions) required editing code and a full
  // rebuild+resideload cycle just to fix connectivity. A user running
  // this day-to-day, not developing it, can't do that. This is a saved
  // override: null means "no override set, use the build-time default in
  // main.dart" (same fallback behavior as before this existed), a real
  // value means the user has corrected it themselves on-device.
  static String? _webDesktopIp;

  Future<String?> getDesktopIp() async {
    if (kIsWeb) return _webDesktopIp;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kDesktopIpKey);
  }

  Future<void> setDesktopIp(String ip) async {
    if (kIsWeb) {
      _webDesktopIp = ip;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDesktopIpKey, ip);
  }

  // ── Bare repo path override ────────────────────────────────────────────────
  // 2026-08-20: real multi-repo gap, found while investigating "add
  // multiple repositories" - bareRepoPath was a build-time constant
  // just like desktopIp used to be, meaning every "Add another vault"
  // attempt pointed at the exact same bare repo no matter which folder
  // was picked - genuine multi-repo (a second vault syncing to its own
  // separate bare repo) wasn't architecturally possible. Same override
  // pattern as desktopIp: null means "use the build-time default," a
  // real value means the user set a specific target for the *next*
  // vault they link (via the Settings screen, before tapping "Add
  // another vault").
  static String? _webBareRepoPath;

  Future<String?> getBareRepoPath() async {
    if (kIsWeb) return _webBareRepoPath;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kBareRepoPathKey);
  }

  Future<void> setBareRepoPath(String path) async {
    if (kIsWeb) {
      _webBareRepoPath = path;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBareRepoPathKey, path);
  }

  // ── Auto-discovery interest capture ────────────────────────────────────────
  // 2026-08-21: mDNS/subnet auto-discovery for the desktop IP was
  // explicitly scoped OUT on 2026-08-20 ("let the user fix it themselves
  // for this session") - real feature, not started. This is NOT that
  // feature. It's a cheap local-only signal: which price point (if any)
  // a user tapped on the "would you pay for this?" prompt in Settings.
  // Stored on-device only, no backend exists to aggregate this across
  // real users yet - honest framing matters here, this is scaffolding
  // for when there IS a user base, not a live pricing experiment today.
  // null = never tapped, otherwise one of the price strings shown in
  // settings_screen.dart's interest card.
  static String? _webAutoDiscoveryInterest;

  Future<String?> getAutoDiscoveryInterest() async {
    if (kIsWeb) return _webAutoDiscoveryInterest;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kAutoDiscoveryInterestKey);
  }

  Future<void> setAutoDiscoveryInterest(String price) async {
    if (kIsWeb) {
      _webAutoDiscoveryInterest = price;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAutoDiscoveryInterestKey, price);
  }

  // ── Resolved-conflict watchlist ────────────────────────────────────────────
  // See resolved_watchlist.dart for what this is and why - the matching/
  // pruning logic itself is pure and unit-tested there, this is just the
  // thin persistence wrapper, same shape as everything else in this file.
  static List<ResolvedRecord> _webResolvedWatchlist = [];

  Future<List<ResolvedRecord>> getResolvedWatchlist() async {
    if (kIsWeb) return List.from(_webResolvedWatchlist);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kResolvedWatchlistKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List<dynamic>)
        .map((m) => ResolvedRecord.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  Future<void> setResolvedWatchlist(List<ResolvedRecord> list) async {
    if (kIsWeb) {
      _webResolvedWatchlist = list;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kResolvedWatchlistKey,
      jsonEncode(list.map((r) => r.toJson()).toList()),
    );
  }

  Future<void> addResolvedRecords(List<ResolvedRecord> records) async {
    final list = await getResolvedWatchlist();
    list.addAll(records);
    await setResolvedWatchlist(list);
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
