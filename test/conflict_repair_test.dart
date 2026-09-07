// 2026-08-19: exercises the "nested/compounding conflict markers" bug
// found on real device 2026-08-18 (see lib/services/conflict_repair.dart
// and MEMORY project_synclocal_app.md's FIFTH real bug) - three rounds
// of an unresolved same-line conflict used to nest one `> ` deeper each
// time, and Obsidian only visually expands the outermost callout, so
// older rounds silently disappeared from view while still sitting
// unresolved in the raw file. This test simulates exactly that
// sequence and asserts the fixed repair logic stays flat and keeps
// every version recoverable instead.

import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/services/conflict_repair.dart';

/// Wraps [ours]/[theirs] in raw git conflict markers, the same shape
/// libgit2 leaves in the working tree on a real merge conflict.
String _markers(String ours, String theirs) =>
    '<<<<<<< HEAD\n$ours\n=======\n$theirs\n>>>>>>> origin/main\n';

void main() {
  group('repairConflictMarkers - single round (regression baseline)', () {
    test('wraps ours/theirs in exactly one sibling pair, no nesting', () {
      final content = _markers('line A', 'line B');
      final out = repairConflictMarkers(content,
          otherLabel: 'Desktop', otherTime: '202608181200');

      expect(out, contains('[!info]+ SYNC CONFLICT - yours'));
      expect(out, contains('[!warning]+ SYNC CONFLICT - Desktop - 202608181200'));
      // Exactly one quote level - never '> >'.
      expect(out.contains('> >'), isFalse);
      expect(out, contains('> line A'));
      expect(out, contains('> line B'));
    });

    test('identical (whitespace-normalized) sides collapse with no callout',
        () {
      final content = _markers('same text', 'same   text');
      final out = repairConflictMarkers(content, otherLabel: 'Desktop');
      expect(out, isNot(contains('SYNC CONFLICT')));
      expect(out.trim(), 'same text');
    });
  });

  group('repairConflictMarkers - repeated rounds on the same line', () {
    test('three unresolved rounds stay flat, never nest, all recoverable',
        () {
      // Round 1: phone and desktop both edit line 1 differently, the
      // user never resolves it before round 2 fires.
      var vault = repairConflictMarkers(
        _markers('phone edit 1', 'desktop edit 1'),
        otherLabel: 'Desktop',
        otherTime: '202608181200',
      );
      expect(vault.contains('> >'), isFalse,
          reason: 'round 1 must never nest - nothing to nest yet');

      // Round 2: the file (still unresolved) gets pulled into ANOTHER
      // conflict - libgit2 marks the whole current content as "ours"
      // against a new "theirs". This is exactly the shape that used to
      // nest one level deeper.
      vault = repairConflictMarkers(
        _markers(vault.trim(), 'phone edit 2'),
        otherLabel: 'Phone',
        otherTime: '202608181300',
      );
      expect(vault.contains('> >'), isFalse,
          reason: 'round 2 must not nest round 1 inside a new wrapper');

      // Round 3: same thing again, a third device weighs in before
      // anything was ever resolved.
      vault = repairConflictMarkers(
        _markers(vault.trim(), 'tablet edit 3'),
        otherLabel: 'Tablet',
        otherTime: '202608181400',
      );
      expect(vault.contains('> >'), isFalse,
          reason: 'round 3 must not nest either - depth must stay bounded '
              'at exactly one quote level no matter how many rounds fire');

      // All four versions (original "yours" plus the three incoming
      // edits) must still be individually present and readable, not
      // buried or dropped - this is the actual data-safety property
      // that matters, nesting depth is just the symptom.
      expect(vault, contains('phone edit 1'));
      expect(vault, contains('desktop edit 1'));
      expect(vault, contains('phone edit 2'));
      expect(vault, contains('tablet edit 3'));

      // And every version must be wrapped as its own sibling callout -
      // Obsidian only auto-expands the outermost/last callout, so a
      // version that isn't its own top-level callout is the exact
      // invisibility trap this fix targets.
      final infoCount = RegExp(r'\[!info\]\+ SYNC CONFLICT').allMatches(vault).length;
      final warningCount =
          RegExp(r'\[!warning\]\+ SYNC CONFLICT').allMatches(vault).length;
      expect(infoCount, 1, reason: 'exactly one "yours" head version');
      expect(warningCount, 3, reason: 'one sibling per incoming round');
    });
  });

  group('repairConflictMarkers - narrow git hunk next to an untouched '
      'older conflict (real device bug, 2026-08-19)', () {
    test('a single-line hunk landing next to an already-stacked callout '
        'still recovers all versions, no duplicate/empty header', () {
      // Exact real-device shape: a note already has one unresolved
      // conflict (an [!info]+ "yours" callout followed by an unrelated
      // [!warning]+ callout further down). The user then edits ONLY the
      // body line under the first callout - not its header - on both
      // phone and desktop, differently. Git's resulting conflict hunk
      // is therefore exactly that one line: the header above it, and
      // the whole second callout below, are untouched and never appear
      // between <<<<<<< and >>>>>>> at all.
      final content = '# Conflict test note\n'
          '\n'
          'Edit the line below differently on phone and desktop.\n'
          '\n'
          '> [!info]+ SYNC CONFLICT - yours (review and delete one)\n'
          '${_markers('> PHONE ROUND 2 EDIT 202608190909', '> DESKTOP ROUND 2 EDIT 202608190909')}'
          '\n'
          '> [!warning]+ SYNC CONFLICT - Desktop test - 202608181955 (review and delete one)\n'
          '> Original line: CHANGED ON DESKTOP 20260818d.\n';

      final out = repairConflictMarkers(content,
          otherLabel: 'desktop obsidian', otherTime: '202608190910');

      // No duplicate/empty "yours" header left dangling with no body -
      // that's what leaked raw header text into the picker's body text
      // on the real device.
      final infoCount =
          RegExp(r'\[!info\]\+ SYNC CONFLICT').allMatches(out).length;
      expect(infoCount, 1,
          reason: 'the old, now-empty duplicate header must be dropped, '
              'not kept as a second info callout');

      // All three real versions must survive: the pre-existing
      // "Desktop test" version, and both sides of the new edit.
      expect(out, contains('PHONE ROUND 2 EDIT 202608190909'));
      expect(out, contains('DESKTOP ROUND 2 EDIT 202608190909'));
      expect(out, contains('CHANGED ON DESKTOP 20260818d.'));

      // The old callout must not be stranded as an orphaned, separately
      // -looking block - every warning callout must have been produced
      // through the same flatten path, so there should be exactly 3
      // total callouts (1 info + 2 warning) with no line consisting of
      // only a header and no body.
      final warningCount =
          RegExp(r'\[!warning\]\+ SYNC CONFLICT').allMatches(out).length;
      expect(warningCount, 2);
    });
  });

  group('consolidateStackedRuns must never merge unrelated conflicts '
      '(real device finding, 2026-08-19 - tried a wider blank-line '
      'tolerance and reverted it)', () {
    test('two genuinely separate conflict blocks, 2 blank lines apart, '
        'stay separate - not merged into one combined list', () {
      // Real device shape: a title-heading conflict and a completely
      // unrelated, later conflict elsewhere in the same note, both
      // written by this app, happened to end up exactly 2 blank lines
      // apart - the same gap size that also appears between true
      // siblings of ONE accumulating conflict elsewhere in real files.
      // There is no reliable way to tell these two shapes apart from
      // blank-line count alone, so the safe choice is to never bridge
      // more than one blank line - under-consolidating (a stale block
      // stays its own entry) is safe; over-consolidating (unrelated
      // content silently offered as one N-way choice) is not.
      const content = '> [!info]+ SYNC CONFLICT - yours (review and delete one)\n'
          '> TITLE PHONE EDIT\n'
          '\n'
          '> [!warning]+ SYNC CONFLICT - Desktop (review and delete one)\n'
          '> TITLE DESKTOP EDIT\n'
          '\n'
          '\n'
          '> [!info]+ SYNC CONFLICT - yours (review and delete one)\n'
          '> UNRELATED PHONE EDIT\n'
          '\n'
          '> [!warning]+ SYNC CONFLICT - Desktop (review and delete one)\n'
          '> UNRELATED DESKTOP EDIT\n';

      final out = consolidateStackedRuns(content);

      // If this were 1, the two unrelated conflicts got merged into a
      // single 4-version list - the exact regression this test exists
      // to catch.
      final infoCount =
          RegExp(r'\[!info\]\+ SYNC CONFLICT').allMatches(out).length;
      expect(infoCount, 2,
          reason: 'each genuinely separate conflict must keep its own '
              '"yours" head version, not be folded into the other');
    });
  });

  group('em dash vs regular dash (real device bug, confirmed same night as '
      'the narrow-hunk fix above)', () {
    test('a stacked block written with the OLD em-dash separator is still '
        'recognized and consolidated, not silently skipped', () {
      // Real device repro: an already-broken block from before the
      // dash fix (nested `> >`, duplicate empty header, em dash
      // throughout) sat completely untouched after a fresh pull -
      // proven by pulling the raw file and finding it byte-identical
      // to before. Root cause: consolidateStackedRuns's own pattern
      // only recognized the NEW regular-dash format it now writes, so
      // it silently failed to even see this text as a conflict block
      // worth consolidating.
      const legacyBlock = '> [!info]+ SYNC CONFLICT — yours (review and delete one)\n'
          '> [!info]+ SYNC CONFLICT — yours (review and delete one)\n'
          '> > PHONE ROUND 2 EDIT 202608190909\n'
          '\n'
          '> [!warning]+ SYNC CONFLICT — desktop obsidian — 202608190910 (review and delete one)\n'
          '> > DESKTOP ROUND 2 EDIT 202608190909\n'
          '\n'
          '\n'
          '> [!warning]+ SYNC CONFLICT — Desktop test — 202608181955 (review and delete one)\n'
          '> Original line: CHANGED ON DESKTOP 20260818d.\n';

      final out = consolidateStackedRuns(legacyBlock);

      final infoCount =
          RegExp(r'\[!info\]\+ SYNC CONFLICT').allMatches(out).length;
      expect(infoCount, 1,
          reason: 'legacy em-dash content must be recognized and the '
              'orphaned duplicate header dropped, same as new-format content');
      expect(out.contains('> >'), isFalse,
          reason: 'legacy nesting must also be flattened, not left as-is');
      expect(out, contains('PHONE ROUND 2 EDIT 202608190909'));
      expect(out, contains('DESKTOP ROUND 2 EDIT 202608190909'));
      expect(out, contains('CHANGED ON DESKTOP 20260818d.'));
    });
  });

  group('extractStackedVersions', () {
    test('plain unwrapped text (never conflicted) returns one synthetic version', () {
      final versions = extractStackedVersions('just some note content');
      expect(versions, hasLength(1));
      expect(versions.single.label, 'yours');
      expect(versions.single.body, 'just some note content');
    });

    test('a real stacked block extracts every version at the right depth',
        () {
      const block = '> [!info]+ SYNC CONFLICT - yours (review and delete one)\n'
          '> v1\n'
          '\n'
          '> [!warning]+ SYNC CONFLICT - Desktop (review and delete one)\n'
          '> v2\n';
      final versions = extractStackedVersions(block);
      expect(versions, hasLength(2));
      expect(versions[0].label, 'yours');
      expect(versions[0].body, 'v1');
      expect(versions[1].label, 'Desktop');
      expect(versions[1].body, 'v2');
    });
  });

  group('journal entries order chronologically, not by arrival '
      '(real 2026-09-07 case: NAB Bills incident review)', () {
    test('review callouts show the earlier HHMM entry first', () {
      final content = _markers(
          '2105 salad Caucasian Swiss? Gave me a hard time.',
          '0715 Clothes washed last night are 80% damp wet.');
      final out = repairConflictMarkers(content,
          otherLabel: 'desktop obsidian', otherTime: '202609041645');

      // The 0715 entry (theirs) happened earlier in the day than the
      // 2105 entry (ours) - it must render first, even though "ours"
      // is always built first in the underlying versions list.
      final theirsPos = out.indexOf('0715 Clothes washed');
      final oursPos = out.indexOf('2105 salad');
      expect(theirsPos, greaterThanOrEqualTo(0));
      expect(oursPos, greaterThanOrEqualTo(0));
      expect(theirsPos, lessThan(oursPos));
    });

    test('an untimed entry (no leading HHMM) leaves arrival order untouched',
        () {
      // Matches the real Aug 28th 2026 case: one side has no timestamp
      // at all, so there is nothing safe to sort by - must not guess.
      final content = _markers(
          '2105 salad Caucasian Swiss? Gave me a hard time.',
          'Clothes washed last night are 80% damp wet.');
      final out = repairConflictMarkers(content, otherLabel: 'Desktop');

      final oursPos = out.indexOf('2105 salad');
      final theirsPos = out.indexOf('Clothes washed');
      expect(oursPos, lessThan(theirsPos));
    });

    test('dedupeAndCheckAppend auto-merge reorders by time, not arrival, '
        'when both sides are timestamped', () {
      // theirs is "ours plus a continuation" (satisfies the overlap>0
      // safety gate), but the new line's own clock time (0100) is
      // earlier than ours' (1200) - naive concatenation would put it
      // last; the real fix must put it first.
      final merged = dedupeAndCheckAppend(
        '1200 noon thing',
        '1200 noon thing\n0100 early thing',
      );
      expect(merged, isNotNull);
      final earlyPos = merged!.indexOf('0100 early thing');
      final noonPos = merged.indexOf('1200 noon thing');
      expect(earlyPos, lessThan(noonPos));
    });
  });

  group('mergeThreeWayLines - the real 2026-09-06 Kanban case and variants',
      () {
    test('disjoint insertions in different sections merge with no conflict',
        () {
      const base = 'A\nB\nC\n\nX\nY\nZ';
      const ours = 'A\nNEW-PHONE\nB\nC\n\nX\nY\nZ';
      const theirs = 'A\nB\nC\n\nX\nNEW-DESKTOP\nY\nZ';
      final merged = mergeThreeWayLines(base, ours, theirs);
      expect(merged, isNotNull);
      expect(merged, contains('NEW-PHONE'));
      expect(merged, contains('NEW-DESKTOP'));
      expect(merged,
          'A\nNEW-PHONE\nB\nC\n\nX\nNEW-DESKTOP\nY\nZ');
    });

    test('one side edits a line the other side never touched - not a conflict',
        () {
      const base = 'A\nB\nC';
      const ours = 'A\nB CHANGED\nC';
      const theirs = 'A\nB\nC';
      expect(mergeThreeWayLines(base, ours, theirs), 'A\nB CHANGED\nC');
    });

    test('both sides change the exact same line differently - real conflict',
        () {
      const base = 'A\nB\nC';
      const ours = 'A\nB FROM PHONE\nC';
      const theirs = 'A\nB FROM DESKTOP\nC';
      expect(mergeThreeWayLines(base, ours, theirs), isNull);
    });

    test(
        'both sides delete the same line - still deferred to manual, same '
        'conservative bias as every other merge path in this app', () {
      const base = 'A\nB\nC';
      const ours = 'A\nC';
      const theirs = 'A\nC';
      expect(mergeThreeWayLines(base, ours, theirs), isNull);
    });

    test('unrelated additions at the exact same gap are both kept', () {
      const base = 'A\nB';
      const ours = 'A\nPHONE ITEM\nB';
      const theirs = 'A\nDESKTOP ITEM\nB';
      expect(mergeThreeWayLines(base, ours, theirs),
          'A\nPHONE ITEM\nDESKTOP ITEM\nB');
    });

    test('one side purely appends at the end, other side is unchanged', () {
      const base = 'A\nB';
      const ours = 'A\nB';
      const theirs = 'A\nB\nC';
      expect(mergeThreeWayLines(base, ours, theirs), 'A\nB\nC');
    });
  });
}
