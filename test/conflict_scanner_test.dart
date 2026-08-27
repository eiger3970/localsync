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

  // 2026-08-25: real feedback, live - "I need all or part of that data
  // onto this device, merged as in gitmerge... similar to a git merge."
  // Picking used to fully discard the other version(s) into a separate
  // backup file - see applyResolution's own 2026-08-25 comment for the
  // fix (append non-chosen versions as a [!question]- callout in the
  // same file, not just a backup).
  group('applyResolution - non-Kanban merge', () {
    test('picking a version keeps the other version\'s text in the file, not just the backup',
        () async {
      final dir = await Directory.systemTemp.createTemp('localsync_test_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/Journal entry.md');
      await file.writeAsString(
        '# Aug 24th\n'
        '\n'
        '> [!warning]+ SYNC CONFLICT — yours (review and delete one)\n'
        '> Fixed the pairing screen this morning.\n'
        '> [!warning]+ SYNC CONFLICT — desktop obsidian - 202608251230 (review and delete one)\n'
        '> Emailed about the domicile case this afternoon.\n'
        '\n'
        'Next entry.\n',
      );

      final entries = await scanForConflicts(dir.path);
      expect(entries, hasLength(1));
      final entry = entries.single;
      expect(entry.isKanban, isFalse);
      expect(entry.versions, hasLength(2));

      final content = await file.readAsString();
      final updated = applyResolution(content, entry, entry.versions[0].body);

      // The chosen text is plain again - no longer flagged as a
      // conflict.
      expect(updated, contains('Fixed the pairing screen this morning.'));
      // The other version's text is still IN THE FILE, not just backed
      // up elsewhere.
      expect(updated,
          contains('Emailed about the domicile case this afternoon.'));
      // 2026-08-26: real feedback, live - "What do I do? Is this an
      // Obsidian error?" - wording changed to spell out "already
      // resolved, not active" directly instead of relying on the
      // [!question]- convention alone.
      expect(updated, contains('Already resolved'));
      expect(updated,
          contains('This is desktop obsidian - 202608251230\'s version'));
      // Different callout kind than SYNC CONFLICT, on purpose - see the
      // next assertion.
      expect(updated, contains('[!question]-'));
      expect(updated, contains('Next entry.'));

      // Re-scanning the resolved file must not find a fresh conflict -
      // [!question]- is deliberately not [!warning]+ SYNC CONFLICT.
      await file.writeAsString(updated);
      final rescanned = await scanForConflicts(dir.path);
      expect(rescanned, isEmpty);
    });

    test('Kanban conflicts are never merge-appended - a card is one line', () async {
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
        '## Done\n',
      );

      final entries = await scanForConflicts(dir.path);
      final entry = entries.single;
      final content = await file.readAsString();
      final updated = applyResolution(content, entry, entry.versions[0].body);

      expect(updated, isNot(contains('[!question]-')));
      expect(updated,
          contains('- [ ] Kanban round 3 phone edit 202608201339\n## Done'));
    });
  });

  // 2026-08-27: real feedback, live - "fear of reversing a mistaken git
  // merge" plus a direct ask to build Undo. See undoReferenceCallout's
  // own doc (conflict_scanner.dart) for why this writes no extra backup.
  group('undoReferenceCallout', () {
    test('swaps the kept text and the reference callout, and undo is reversible',
        () async {
      final dir = await Directory.systemTemp.createTemp('localsync_test_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/Journal entry.md');
      await file.writeAsString(
        '# Aug 24th\n'
        '\n'
        '> [!warning]+ SYNC CONFLICT — yours (review and delete one)\n'
        '> Fixed the pairing screen this morning.\n'
        '> [!warning]+ SYNC CONFLICT — desktop obsidian - 202608251230 (review and delete one)\n'
        '> Emailed about the domicile case this afternoon.\n'
        '\n'
        'Next entry.\n',
      );

      final entries = await scanForConflicts(dir.path);
      final entry = entries.single;
      final resolved =
          applyResolution(await file.readAsString(), entry, entry.versions[0].body);
      await file.writeAsString(resolved);

      // Real span exists now, so Undo is offered.
      final refs = await scanForReferenceCallouts(dir.path);
      expect(refs, hasLength(1));
      final ref = refs.single;
      expect(ref.keptMarkerStart, isNotNull);
      expect(ref.keptContent, contains('Fixed the pairing screen'));

      await undoReferenceCallout(dir.path, ref);
      final afterUndo = await file.readAsString();

      // The previously-dropped side is now the active, kept content.
      expect(afterUndo, contains('Emailed about the domicile case this afternoon.'));
      // The previously-kept side is now the reference leftover.
      expect(afterUndo, contains('Already resolved'));
      expect(afterUndo, contains("This is Your version's version"));
      expect(afterUndo, contains('Fixed the pairing screen this morning.'));
      expect(afterUndo, contains('Next entry.'));

      // Undoing again swaps it right back - reversible both ways.
      final refsAfter = await scanForReferenceCallouts(dir.path);
      expect(refsAfter.single.keptMarkerStart, isNotNull);
      await undoReferenceCallout(dir.path, refsAfter.single);
      final afterSecondUndo = await file.readAsString();
      expect(afterSecondUndo, contains('Fixed the pairing screen this morning.'));
      expect(
          afterSecondUndo, contains("This is desktop obsidian - 202608251230's version"));
    });

    test('an old note with no LOCALSYNC-KEPT marker has no undoable span',
        () async {
      final dir = await Directory.systemTemp.createTemp('localsync_test_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/Legacy note.md');
      // Hand-written, pre-marker shape - what an older resolved note
      // looks like on disk (no <!-- LOCALSYNC-KEPT --> wrapper).
      await file.writeAsString(
        'Kept text from before this marker existed.\n'
        '\n'
        '> [!question]- Already resolved - kept for reference only, not '
        'an active conflict. This is yours\'s version that was NOT kept - '
        'copy anything you want from it, then delete this block whenever.\n'
        '> Old dropped text.\n',
      );

      final refs = await scanForReferenceCallouts(dir.path);
      expect(refs, hasLength(1));
      expect(refs.single.keptMarkerStart, isNull);
      expect(refs.single.keptContent, isNull);

      // Calling undo on it is a safe no-op, not a crash.
      final before = await file.readAsString();
      await undoReferenceCallout(dir.path, refs.single);
      expect(await file.readAsString(), before);
    });
  });
}
