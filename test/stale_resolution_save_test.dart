import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/services/pre_pull_marker.dart';

// 2026-11-17 real Test E2: Obsidian saved its old copy over a KEEP BOTH & CLEAN UP fix.
void main() {
  late Directory vault;
  setUp(() {
    vault = Directory.systemTemp.createTempSync('stale_fix');
    Directory('${vault.path}/.git').createSync();
  });
  tearDown(() => vault.deleteSync(recursive: true));

  const before = 'HHMM test E3 DESKTOP\n';
  const after = 'HHMM test E3 PHONE\n\nHHMM test E3 DESKTOP\n';

  test('old copy written back over the fix -> fix written again', () {
    final f = File('${vault.path}/n.md')..writeAsStringSync(after);
    noteResolution(vault.path, 'n.md', before, after);
    f.writeAsStringSync(before); // Obsidian's stale save
    expect(restoreStaleResolutionSaves(vault.path), ['n.md']);
    expect(f.readAsStringSync(), after);
  });

  test('new typing on top is left alone', () {
    final f = File('${vault.path}/n.md')..writeAsStringSync(after);
    noteResolution(vault.path, 'n.md', before, after);
    f.writeAsStringSync('$after\n1100 new line\n');
    expect(restoreStaleResolutionSaves(vault.path), isEmpty);
    expect(f.readAsStringSync(), '$after\n1100 new line\n');
  });

  test('UNDO is never re-fixed', () {
    final f = File('${vault.path}/n.md')..writeAsStringSync(after);
    noteResolution(vault.path, 'n.md', before, after);
    forgetResolution(vault.path, 'n.md');
    f.writeAsStringSync(before);
    expect(restoreStaleResolutionSaves(vault.path), isEmpty);
    expect(f.readAsStringSync(), before);
  });
}
