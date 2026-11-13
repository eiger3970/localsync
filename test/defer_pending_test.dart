import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/services/sync_service.dart';
import 'package:localsync/services/conflict_scanner.dart';

void main() {
  test('a clash the merge cannot decide: no boxes in the note, a pending pair instead (2026-11-14)', () async {
    final d = Directory.systemTemp.createTempSync('defer');
    final note = File('${d.path}/Journal/Nov 13th, 2026.md')..createSync(recursive: true);
    note.writeAsStringSync('0626 base\n\n<<<<<<< HEAD\nMetro thoughts.\n\n2000 test phone\n=======\n1900 test desktop\n>>>>>>> origin/main\n');
    expect(deferConflictsToPending(d.path), 1);
    final text = note.readAsStringSync();
    expect(text, '0626 base\n\n1900 test desktop\n');
    expect(text.contains('SYNC CONFLICT'), isFalse);
    final pend = await scanPendingConflicts(d.path);
    expect(pend.length, 1);
    expect(pend.first.versions.first.body, 'Metro thoughts.\n\n2000 test phone');
    expect(pend.first.versions.last.body, '1900 test desktop');
    d.deleteSync(recursive: true);
  });
}
