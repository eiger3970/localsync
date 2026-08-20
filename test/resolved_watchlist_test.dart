// 2026-08-20: exercises the revert-detection safety net added after the
// real device finding (2026-08-19) that a resolved conflict can silently
// reappear, most likely Obsidian's own cache clobbering the coordinated
// write - see lib/services/resolved_watchlist.dart's header for the full
// reasoning. This only tests the pure matching/pruning logic, not the
// shared_preferences storage wrapper (DatabaseService) or the actual
// on-device cache behavior, which can't be simulated here.

import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/services/conflict_scanner.dart';
import 'package:localsync/services/resolved_watchlist.dart';

ConflictEntry _entry(String filePath, List<ConflictVersion> versions) =>
    ConflictEntry(
      filePath: filePath,
      versions: versions,
      isKanban: false,
      matchStart: 0,
      matchEnd: 0,
    );

void main() {
  group('recordsFor', () {
    test('one record per non-"yours" version, skipping index 0', () {
      final entry = _entry('note.md', [
        const ConflictVersion(who: 'yours', body: 'mine'),
        const ConflictVersion(who: 'Desktop', when: '202608201000', body: 'theirs'),
      ]);
      final records = recordsFor(entry, DateTime(2026, 8, 20));
      expect(records, hasLength(1));
      expect(records.single.who, 'Desktop');
      expect(records.single.when, '202608201000');
      expect(records.single.filePath, 'note.md');
    });

    test('a 3-way stacked entry produces a record per other version', () {
      final entry = _entry('note.md', [
        const ConflictVersion(who: 'yours', body: 'mine'),
        const ConflictVersion(who: 'Desktop', when: 't1', body: 'a'),
        const ConflictVersion(who: 'Phone', when: 't2', body: 'b'),
      ]);
      expect(recordsFor(entry, DateTime(2026, 8, 20)), hasLength(2));
    });
  });

  group('findReverted', () {
    test('flags a watchlist entry that reappears in a fresh scan', () {
      final watchlist = [
        ResolvedRecord(
            filePath: 'note.md',
            who: 'Desktop',
            when: '202608201000',
            resolvedAt: DateTime(2026, 8, 20)),
      ];
      final freshScan = [
        _entry('note.md', [
          const ConflictVersion(who: 'yours', body: 'mine'),
          const ConflictVersion(
              who: 'Desktop', when: '202608201000', body: 'theirs'),
        ]),
      ];
      expect(findReverted(freshScan, watchlist), hasLength(1));
    });

    test('does not flag an unrelated new conflict in the same file', () {
      final watchlist = [
        ResolvedRecord(
            filePath: 'note.md',
            who: 'Desktop',
            when: '202608201000',
            resolvedAt: DateTime(2026, 8, 20)),
      ];
      // Same file, same device name, but a genuinely different (later)
      // timestamp - a real new conflict, not the old one coming back.
      final freshScan = [
        _entry('note.md', [
          const ConflictVersion(who: 'yours', body: 'mine'),
          const ConflictVersion(
              who: 'Desktop', when: '202608201500', body: 'something new'),
        ]),
      ];
      expect(findReverted(freshScan, watchlist), isEmpty);
    });

    test('does not flag when the file has no conflicts at all', () {
      final watchlist = [
        ResolvedRecord(
            filePath: 'note.md',
            who: 'Desktop',
            when: '202608201000',
            resolvedAt: DateTime(2026, 8, 20)),
      ];
      expect(findReverted([], watchlist), isEmpty);
    });
  });

  group('pruneOld', () {
    test('drops entries older than maxAge, keeps recent ones', () {
      final now = DateTime(2026, 8, 20, 12, 0);
      final watchlist = [
        ResolvedRecord(
            filePath: 'old.md', who: 'Desktop', resolvedAt: now.subtract(const Duration(days: 10))),
        ResolvedRecord(
            filePath: 'recent.md', who: 'Desktop', resolvedAt: now.subtract(const Duration(hours: 1))),
      ];
      final result = pruneOld(watchlist, now);
      expect(result, hasLength(1));
      expect(result.single.filePath, 'recent.md');
    });
  });
}
