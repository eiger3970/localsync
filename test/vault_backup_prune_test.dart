// 2026-09-06: exercises pruneOldConflictBackups (services/vault_backup.dart)
// - real feedback, "will backups fill up a user's phone storage?" Pure
// dart:io logic, no git2dart involved, so this runs and proves itself
// locally same as everything else added today.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/services/vault_backup.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('localsync_prune_test');
    await Directory('${tmp.path}/$kLocalSyncFolderName/Conflict Backups')
        .create(recursive: true);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  String _ts(DateTime d) {
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${d.year}${p2(d.month)}${p2(d.day)}${p2(d.hour)}${p2(d.minute)}';
  }

  Future<void> _write(String name) async {
    await File(
            '${tmp.path}/$kLocalSyncFolderName/Conflict Backups/$name')
        .writeAsString('content');
  }

  test('deletes backups older than maxAge, keeps recent ones', () async {
    final old = DateTime.now().subtract(const Duration(days: 40));
    final recent = DateTime.now().subtract(const Duration(days: 2));
    await _write('Note A - before pull reset - ${_ts(old)}.md');
    await _write('Note B - before push-retry reset - ${_ts(recent)}.md');

    await pruneOldConflictBackups(tmp.path);

    final remaining = await Directory(
            '${tmp.path}/$kLocalSyncFolderName/Conflict Backups')
        .list()
        .map((e) => e.uri.pathSegments.last)
        .toList();
    expect(remaining, hasLength(1));
    expect(remaining.single, contains('Note B'));
  });

  test('leaves a file with no parseable timestamp alone', () async {
    await _write('mystery-file-no-timestamp.md');

    await pruneOldConflictBackups(tmp.path);

    final remaining = await Directory(
            '${tmp.path}/$kLocalSyncFolderName/Conflict Backups')
        .list()
        .toList();
    expect(remaining, hasLength(1));
  });

  test('missing Conflict Backups folder is a safe no-op', () async {
    final emptyVault =
        await Directory.systemTemp.createTemp('localsync_prune_empty');
    try {
      await pruneOldConflictBackups(emptyVault.path);
    } finally {
      await emptyVault.delete(recursive: true);
    }
  });
}
