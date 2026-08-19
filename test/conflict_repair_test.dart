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

      expect(out, contains('[!info]+ SYNC CONFLICT — yours'));
      expect(out, contains('[!warning]+ SYNC CONFLICT — Desktop — 202608181200'));
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

  group('extractStackedVersions', () {
    test('plain unwrapped text (never conflicted) returns one synthetic version', () {
      final versions = extractStackedVersions('just some note content');
      expect(versions, hasLength(1));
      expect(versions.single.label, 'yours');
      expect(versions.single.body, 'just some note content');
    });

    test('a real stacked block extracts every version at the right depth',
        () {
      const block = '> [!info]+ SYNC CONFLICT — yours (review and delete one)\n'
          '> v1\n'
          '\n'
          '> [!warning]+ SYNC CONFLICT — Desktop (review and delete one)\n'
          '> v2\n';
      final versions = extractStackedVersions(block);
      expect(versions, hasLength(2));
      expect(versions[0].label, 'yours');
      expect(versions[0].body, 'v1');
      expect(versions[1].label, 'Desktop');
      expect(versions[1].body, 'v2');
    });
  });
}
