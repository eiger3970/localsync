// services/demo_conflict.dart
//
// 2026-09-26: user - "a test conflict with each app download, so users can
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

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/repository.dart';

const kDemoBookmarkPrefix = 'localsync-demo:';
const _stageKey = 'demo_conflict_stage';

/// 2026-10-06: Kevin - "make a fun conflict that is good for marketing",
/// then "add some romance and a date too" - Valentine's Day in Zermatt.
/// Two versions of the same trip plan: edited on the phone on the train,
/// and on the computer at home. Every entry starts with a clock time and
/// the times cross between the sides, so Auto merge visibly interleaves
/// them into one day.
const kDemoConflictFile = 'Zermatt weekend.md';
const kDemoConflictNote = '# Zermatt weekend - Saturday 14 February\n'
    '\n'
    '> [!warning]+ SYNC CONFLICT — yours (review and delete one)\n'
    '> 0800 Train to Zermatt. Window seat for the first Matterhorn view.\n'
    '> \n'
    '> 1500 Snowball fight with Sam at the glacier. Loser buys hot chocolate.\n'
    '> \n'
    '> 2200 Stargazing on the balcony with Alex, one blanket, two hot chocolates.\n'
    '> [!warning]+ SYNC CONFLICT — desktop - 202602141230 (review and delete one)\n'
    '> 1230 Raclette at the mountain hut, extra pickles.\n'
    '> \n'
    '> 1930 Valentine\'s dinner date with Alex. Candlelit table booked, roses on the way.\n'
    '\n';

class DemoConflict {
  /// 2026-09-26: user - "Shouldn't Conflicts be amber as there's a test
  /// conflict in there?" True while the sample still has a free try, so
  /// the main screen's Conflicts icon can glow amber for it too.
  static final triesLeft = ValueNotifier<bool>(true);

  static Future<int> stage() async {
    final s = (await SharedPreferences.getInstance()).getInt(_stageKey) ?? 0;
    triesLeft.value = s < 2;
    return s;
  }

  /// Called after a demo resolution finishes; only moves forward.
  static Future<void> advancePast(int finishedStage) async {
    final prefs = await SharedPreferences.getInstance();
    final now = prefs.getInt(_stageKey) ?? 0;
    if (finishedStage >= now) await prefs.setInt(_stageKey, finishedStage + 1);
    triesLeft.value = (prefs.getInt(_stageKey) ?? 0) < 2;
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
    await File('${dir.path}/$kDemoConflictFile').writeAsString(kDemoConflictNote);
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
