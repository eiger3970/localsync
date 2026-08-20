// 2026-08-20: exercises the real device bug found live during a Kanban
// conflict test - resolving a card conflict merged the picked card text
// directly onto the following "## Done" heading with no line break,
// breaking the board's structure. Root cause: resolveConflict() always
// omitted a trailing newline for Kanban resolutions, on the wrong
// assumption a Kanban conflict never needs one - but the matched span
// often does consume a real trailing newline (whenever the conflict
// isn't the very last thing in the file), so dropping it merged two
// lines together. See lib/services/conflict_scanner.dart's
// applyResolution for the fix.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/services/conflict_scanner.dart';

void main() {
  group('applyResolution - Kanban', () {
    test(
        'resolving a card conflict followed by another heading keeps them on separate lines '
        '(regression: real device bug, merged onto one line)', () async {
      final dir = await Directory.systemTemp.createTemp('localsync_test_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/Board daily stuff.md');
      await file.writeAsString(
        '---\n'
        'kanban-plugin: board\n'
        '---\n'
        '\n'
        '## To Do\n'
        '\n'
        '- [ ] Kanban round 3 phone edit 202608201339\n'
        '%% CONFLICT-OTHER (Desktop test - 202608201801): '
        '- [ ] Kanban round 3 desktop edit 202608201801 %%\n'
        '## Done\n'
        '\n'
        '\n'
        '%% kanban:settings\n'
        '```\n'
        '{"kanban-plugin":"board"}\n'
        '```\n'
        '%%\n',
      );

      final entries = await scanForConflicts(dir.path);
      expect(entries, hasLength(1));
      final entry = entries.single;
      expect(entry.isKanban, isTrue);

      final content = await file.readAsString();
      final updated = applyResolution(content, entry, entry.versions[0].body);

      expect(updated, contains('- [ ] Kanban round 3 phone edit 202608201339\n## Done'));
      // The real bug: no newline between the card and the heading.
      expect(updated, isNot(contains('202608201339## Done')));
    });

    test('resolving a conflict that is the last thing in the file adds no stray newline',
        () async {
      final dir = await Directory.systemTemp.createTemp('localsync_test_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/Board daily stuff.md');
      await file.writeAsString(
        '---\n'
        'kanban-plugin: board\n'
        '---\n'
        '\n'
        '## To Do\n'
        '\n'
        '- [ ] Last card 202608201339\n'
        '%% CONFLICT-OTHER (Desktop test - 202608201801): '
        '- [ ] Last card desktop 202608201801 %%',
      );

      final entries = await scanForConflicts(dir.path);
      expect(entries, hasLength(1));
      final entry = entries.single;

      final content = await file.readAsString();
      final updated = applyResolution(content, entry, entry.versions[0].body);

      expect(updated, endsWith('- [ ] Last card 202608201339'));
      expect(updated.endsWith('\n'), isFalse);
    });
  });
}
