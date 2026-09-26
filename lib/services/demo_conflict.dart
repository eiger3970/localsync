// services/demo_conflict.dart
//
// 2026-09-26: Ken - "a test conflict with each app download, so users can
// test the auto merge convenience once, then downgrade to the merge
// picker, then all locked until paid". The sample note lives in the
// app's own private storage - never inside any synced folder - so the
// demo can't touch a user's real files ("never lose data" rule).
//
// Free tries run in order and only on this sample:
//   stage 0 -> Auto merge (Keep both and clean up) free once
//   stage 1 -> Visual picker (tap to keep a side) free once
//   stage 2 -> both behave like real conflicts (paywalls)
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/repository.dart';

const kDemoBookmarkPrefix = 'localsync-demo:';
const _stageKey = 'demo_conflict_stage';

/// Two versions of the same diary note, written on two devices. Every
/// entry starts with a clock time and the times cross between the sides,
/// so Auto merge visibly interleaves them in time order.
const kDemoConflictNote = '# Diary - Saturday\n'
    '\n'
    '> [!warning]+ SYNC CONFLICT — yours (review and delete one)\n'
    '> 0730 Coffee on the balcony. Three things I am grateful for.\n'
    '> \n'
    '> 1830 Called Mum. Promised to visit next weekend.\n'
    '> [!warning]+ SYNC CONFLICT — desktop - 202609261215 (review and delete one)\n'
    '> 1215 Lunch idea: start the herb garden this spring.\n'
    '> \n'
    '> 2145 Private: still thinking about the job offer.\n'
    '\n';

class DemoConflict {
  static Future<int> stage() async =>
      (await SharedPreferences.getInstance()).getInt(_stageKey) ?? 0;

  /// Called after a demo resolution finishes; only moves forward.
  static Future<void> advancePast(int finishedStage) async {
    final prefs = await SharedPreferences.getInstance();
    final now = prefs.getInt(_stageKey) ?? 0;
    if (finishedStage >= now) await prefs.setInt(_stageKey, finishedStage + 1);
  }

  static bool isDemo(Repository repo) =>
      repo.vaultBookmark.startsWith(kDemoBookmarkPrefix);

  /// Fresh sample every time it's opened, so there's always a conflict
  /// to look at, even after a free try used it up.
  static Future<Repository> prepare() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/localsync_demo');
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    await File('${dir.path}/Diary - Saturday.md').writeAsString(kDemoConflictNote);
    return Repository(
      name: 'Sample',
      remoteHost: '',
      remoteUser: '',
      remotePath: '',
      localPath: dir.path,
      vaultBookmark: '$kDemoBookmarkPrefix${dir.path}',
      obsidianVaultPath: '',
      autoSync: false,
      syncMode: SyncMode.genericFolder,
    );
  }
}
