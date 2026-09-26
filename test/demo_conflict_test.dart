import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:localsync/services/conflict_scanner.dart';
import 'package:localsync/services/demo_conflict.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('demo note is one real conflict with two versions', () async {
    final dir = await Directory.systemTemp.createTemp('localsync_demo_');
    addTearDown(() => dir.delete(recursive: true));
    await File('${dir.path}/Diary - Saturday.md').writeAsString(kDemoConflictNote);
    final entries = await scanForConflicts(dir.path);
    expect(entries, hasLength(1));
    expect(entries.single.versions, hasLength(2));
  });

  test('auto merge interleaves the demo entries in clock order', () async {
    final dir = await Directory.systemTemp.createTemp('localsync_demo_');
    addTearDown(() => dir.delete(recursive: true));
    final f = File('${dir.path}/Diary - Saturday.md');
    await f.writeAsString(kDemoConflictNote);
    final entry = (await scanForConflicts(dir.path)).single;
    await mergeConflictKeepingBoth(dir.path, entry, cleanUp: true);
    final out = await f.readAsString();
    expect(out, isNot(contains('SYNC CONFLICT')));
    final order = ['0730', '1215', '1830', '2145'].map(out.indexOf).toList();
    expect(order.every((i) => i >= 0), isTrue);
    expect(order, orderedEquals([...order]..sort()));
  });

  test('free tries only move forward', () async {
    expect(await DemoConflict.stage(), 0);
    await DemoConflict.advancePast(0);
    expect(await DemoConflict.stage(), 1);
    await DemoConflict.advancePast(0);
    expect(await DemoConflict.stage(), 1);
    await DemoConflict.advancePast(1);
    expect(await DemoConflict.stage(), 2);
  });
}
