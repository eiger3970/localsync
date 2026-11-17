import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:localsync/services/conflict_scanner.dart';

// 2026-11-17 owner, choice B: a KEEP BOTH & CLEAN UP fix is listed in Merged conflicts, and its UNDO works there.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory vault;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    vault = Directory.systemTemp.createTempSync('cleanup_undo');
    Directory('${vault.path}/.git').createSync();
  });
  tearDown(() => vault.deleteSync(recursive: true));

  test('CLEAN UP fix listed, UNDO puts the note back, then gone from the list', () async {
    const before = '1030 coffee\n\nTwo desktop\n';
    final note = File('${vault.path}/day.md')..writeAsStringSync(before);
    final at = before.indexOf('Two desktop');
    final entry = ConflictEntry(
        filePath: 'day.md',
        versions: [ConflictVersion(who: 'yours', body: 'Two phone'), ConflictVersion(who: 'desktop obsidian', body: 'Two desktop')],
        isKanban: false, matchStart: at, matchEnd: at + 'Two desktop'.length);
    final r = await mergeConflictKeepingBoth(vault.path, entry, cleanUp: true);
    expect(r.undo, isNotNull);
    final listed = (await scanForKeptBoth(vault.path)).where((e) => e.wholeNote != null).toList();
    expect(listed.length, 1);
    expect(await undoMerge(vault.path, listed.first.wholeNote!), isTrue);
    expect(note.readAsStringSync(), before);
    expect((await scanForKeptBoth(vault.path)).where((e) => e.wholeNote != null), isEmpty);
  });
}
