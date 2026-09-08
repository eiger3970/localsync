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
      // 2026-09-08: keepLeftoverInNote is now opt-in (default changed to
      // fully remove, matching the confirm dialog's own wording) - this
      // test is specifically about the opt-in path, so it asks for it
      // explicitly rather than relying on a default that no longer holds.
      final updated = applyResolution(content, entry, entry.versions[0].body,
          keepLeftoverInNote: true);

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

    // 2026-09-08: real feedback, live - "gone entirely." The confirm
    // dialog already promised "Removes the other version from this
    // note" while the code actually kept it - this is the new default,
    // matching that promise for real. keepLeftoverInNote defaults to
    // false (see DatabaseService.getKeepLeftoverInNote's own doc).
    test('by default, the other version is fully removed, not kept as a reference',
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
      final content = await file.readAsString();
      final updated = applyResolution(content, entry, entry.versions[0].body);

      expect(updated, contains('Fixed the pairing screen this morning.'));
      expect(updated,
          isNot(contains('Emailed about the domicile case this afternoon.')));
      expect(updated, isNot(contains('Already resolved')));
      expect(updated, isNot(contains('[!question]-')));
      expect(updated, contains('Next entry.'));

      await file.writeAsString(updated);
      expect(await scanForConflicts(dir.path), isEmpty);
      expect(await scanForReferenceCallouts(dir.path), isEmpty);
    });
  });

  group('applyKeepBoth - real 2026-09-07 case (NAB Bills incident review)',
      () {
    test('two unrelated entries land as plain text, ordered chronologically '
        'when both have a leading HHMM time', () async {
      final dir = await Directory.systemTemp.createTemp('localsync_test_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/Aug 28th, 2026.md');
      await file.writeAsString(
        '> [!info]+ SYNC CONFLICT - yours (review and delete one)\n'
        '> 2105 salad Caucasian Swiss? Gave me a hard time.\n'
        '\n'
        '> [!warning]+ SYNC CONFLICT - desktop obsidian - 202609041645 (review and delete one)\n'
        '> 0715 Clothes washed last night are 80% damp wet.\n',
      );

      final entries = await scanForConflicts(dir.path);
      expect(entries, hasLength(1));
      final entry = entries.single;
      final content = await file.readAsString();
      final updated = applyKeepBoth(content, entry);

      // No longer flagged as a conflict - both are just plain text now.
      expect(updated, isNot(contains('SYNC CONFLICT')));
      expect(updated, contains('0715 Clothes washed'));
      expect(updated, contains('2105 salad'));
      // Chronological, not arrival order - 0715 happened before 2105.
      expect(updated.indexOf('0715 Clothes washed'),
          lessThan(updated.indexOf('2105 salad')));

      // Re-scanning must not find a fresh conflict.
      await file.writeAsString(updated);
      expect(await scanForConflicts(dir.path), isEmpty);
    });

    test('an untimed version leaves stacking order untouched - never guesses',
        () async {
      final dir = await Directory.systemTemp.createTemp('localsync_test_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/note.md');
      await file.writeAsString(
        '> [!info]+ SYNC CONFLICT - yours (review and delete one)\n'
        '> 2105 salad Caucasian Swiss? Gave me a hard time.\n'
        '\n'
        '> [!warning]+ SYNC CONFLICT - Desktop (review and delete one)\n'
        '> Clothes washed last night are 80% damp wet.\n',
      );

      final entries = await scanForConflicts(dir.path);
      final entry = entries.single;
      final content = await file.readAsString();
      final updated = applyKeepBoth(content, entry);

      // "yours" (index 0) still comes first - the untimed side gives
      // nothing safe to sort by.
      expect(updated.indexOf('2105 salad'),
          lessThan(updated.indexOf('Clothes washed')));
    });

    test('3+ stacked versions are all kept, none dropped', () async {
      final dir = await Directory.systemTemp.createTemp('localsync_test_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/note.md');
      await file.writeAsString(
        '> [!info]+ SYNC CONFLICT - yours (review and delete one)\n'
        '> 0900 first round.\n'
        '\n'
        '> [!warning]+ SYNC CONFLICT - Desktop - 1 (review and delete one)\n'
        '> 1000 second round.\n'
        '\n'
        '> [!warning]+ SYNC CONFLICT - Desktop - 2 (review and delete one)\n'
        '> 0800 third round.\n',
      );

      final entries = await scanForConflicts(dir.path);
      final entry = entries.single;
      expect(entry.versions, hasLength(3));
      final content = await file.readAsString();
      final updated = applyKeepBoth(content, entry);

      expect(updated, contains('first round'));
      expect(updated, contains('second round'));
      expect(updated, contains('third round'));
      // All three have a leading HHMM - chronological: 0800, 0900, 1000.
      expect(updated.indexOf('third round'), lessThan(updated.indexOf('first round')));
      expect(updated.indexOf('first round'), lessThan(updated.indexOf('second round')));
    });

    test('Kanban conflicts are also supported - both cards kept as plain lines',
        () async {
      final dir = await Directory.systemTemp.createTemp('localsync_test_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/Board.md');
      await file.writeAsString(
        '---\nkanban-plugin: board\n---\n\n'
        '## Bills\n\n'
        '- [ ] Rent due\n'
        '%% CONFLICT-OTHER (Desktop): - [ ] Internet due %%\n',
      );

      final entries = await scanForConflicts(dir.path);
      final entry = entries.single;
      expect(entry.isKanban, isTrue);
      final content = await file.readAsString();
      final updated = applyKeepBoth(content, entry);

      expect(updated, isNot(contains('CONFLICT-OTHER')));
      expect(updated, contains('Rent due'));
      expect(updated, contains('Internet due'));
    });
  });

  group('applyResolution - non-Kanban merge (continued)', () {
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
      final resolved = applyResolution(
          await file.readAsString(), entry, entry.versions[0].body,
          keepLeftoverInNote: true);
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

  group('mergeReferenceKeepingBoth - real 2026-09-07 case (Aug 24th note)',
      () {
    test(
        'chronologically combines the kept and dropped sides when both have a leading time',
        () async {
      final dir = await Directory.systemTemp.createTemp('localsync_test_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/Aug 24th, 2026.md');
      await file.writeAsString(
        '# Aug 24th\n'
        '\n'
        '> [!warning]+ SYNC CONFLICT — yours (review and delete one)\n'
        '> 2105 salad and rice for dinner.\n'
        '> [!warning]+ SYNC CONFLICT — desktop obsidian - 202608251230 (review and delete one)\n'
        '> 1500 went to Point D\'eau for a shower.\n'
        '\n'
        'Next entry.\n',
      );

      final entries = await scanForConflicts(dir.path);
      final entry = entries.single;
      // Keep the phone ("yours"/2105) side, same as the real incident.
      final resolved = applyResolution(
          await file.readAsString(), entry, entry.versions[0].body,
          keepLeftoverInNote: true);
      await file.writeAsString(resolved);

      final refs = await scanForReferenceCallouts(dir.path);
      final ref = refs.single;
      expect(ref.keptMarkerStart, isNotNull);

      await mergeReferenceKeepingBoth(dir.path, ref);
      final merged = await file.readAsString();

      // Both texts survive, as plain paragraphs - no callout, no marker.
      expect(merged, contains('2105 salad and rice for dinner.'));
      expect(merged, contains('1500 went to Point D\'eau for a shower.'));
      expect(merged, isNot(contains('SYNC CONFLICT')));
      expect(merged, isNot(contains('Already resolved')));
      expect(merged, isNot(contains('LOCALSYNC-KEPT')));
      // 1500 comes before 2105 - chronological, not kept-first.
      expect(merged.indexOf('1500'), lessThan(merged.indexOf('2105')));
      expect(merged, contains('Next entry.'));

      // Nothing lost - a backup of both sides exists.
      final backupDir = Directory('${dir.path}/LocalSync/Conflict Backups');
      expect(await backupDir.exists(), isTrue);
      final backups = await backupDir.list().toList();
      expect(backups, hasLength(1));
      final backupContent = await File(backups.single.path).readAsString();
      expect(backupContent, contains('2105 salad and rice for dinner.'));
      expect(backupContent, contains('1500 went to Point D\'eau for a shower.'));
    });

    test('an old note with no LOCALSYNC-KEPT marker has nothing to merge against',
        () async {
      final dir = await Directory.systemTemp.createTemp('localsync_test_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/Legacy note.md');
      await file.writeAsString(
        'Kept text from before this marker existed.\n'
        '\n'
        '> [!question]- Already resolved - kept for reference only, not '
        'an active conflict. This is yours\'s version that was NOT kept - '
        'copy anything you want from it, then delete this block whenever.\n'
        '> Old dropped text.\n',
      );

      final refs = await scanForReferenceCallouts(dir.path);
      expect(refs.single.keptMarkerStart, isNull);

      // Safe no-op, not a crash - same guard as undoReferenceCallout.
      final before = await file.readAsString();
      await mergeReferenceKeepingBoth(dir.path, refs.single);
      expect(await file.readAsString(), before);
    });
  });
}
