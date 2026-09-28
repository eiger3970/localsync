// 2026-09-28: real vault - 130 of 422 Conflict Backups were byte-identical
// copies of an earlier backup of the same note.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/services/localsync_folder.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('backup_dedupe_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('identical backup of the same note is reused, not written again', () {
    final bytes = utf8.encode('1030 police visit.\n');
    final first = saveBackupUnlessIdentical(
        dir, 'Sep 28th - before pull reset - 202609281100.md', bytes);
    final second = saveBackupUnlessIdentical(
        dir, 'Sep 28th - before pull reset - 202609281200.md', bytes);
    expect(second, first);
    expect(dir.listSync(), hasLength(1));
  });

  test('changed content is always written', () {
    saveBackupUnlessIdentical(
        dir, 'Sep 28th - before pull reset - 202609281100.md', utf8.encode('a entry\n'));
    saveBackupUnlessIdentical(
        dir, 'Sep 28th - before pull reset - 202609281200.md', utf8.encode('b entry\n'));
    expect(dir.listSync(), hasLength(2));
  });

  test('same text in a different note is still backed up', () {
    final bytes = utf8.encode('same text\n');
    saveBackupUnlessIdentical(dir, 'Note A - yours - 202609281100.md', bytes);
    saveBackupUnlessIdentical(dir, 'Note B - yours - 202609281100.md', bytes);
    expect(dir.listSync(), hasLength(2));
  });
}
