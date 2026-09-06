import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/services/backup_compare.dart';

void main() {
  group('originalFileNameFromBackup', () {
    test('recovers a simple note name', () {
      expect(
          originalFileNameFromBackup(
              'Board daily stuff - desktop version - 202609060919.md'),
          'Board daily stuff.md');
    });

    test('recovers a note name that itself contains a dash', () {
      expect(
          originalFileNameFromBackup(
              'Sep 5th, 2026 - before pull reset - 202609061125.md'),
          'Sep 5th, 2026.md');
    });

    test('handles the auto-merge labels (which contain a comma)', () {
      expect(
          originalFileNameFromBackup(
              'Board daily stuff - before auto-merge, phone version - 202609061200.md'),
          'Board daily stuff.md');
      expect(
          originalFileNameFromBackup(
              'Board daily stuff - before auto-merge, desktop version - 202609061200.md'),
          'Board daily stuff.md');
    });

    test('handles a file with no extension', () {
      expect(
          originalFileNameFromBackup(
              'README - before push-retry reset - 202609061200'),
          'README');
    });

    test('returns null for a name matching no known label', () {
      expect(
          originalFileNameFromBackup('some random file I dropped here.md'),
          isNull);
    });

    test('returns null for an empty stem', () {
      expect(
          originalFileNameFromBackup(' - desktop version - 202609060919.md'),
          isNull);
    });
  });

  group('matchingLivePaths', () {
    test('finds the single match by filename regardless of folder', () {
      final all = [
        'Board Kanban/Board daily stuff.md',
        'Journal/2026/09/Sep 5th, 2026.md',
      ];
      expect(matchingLivePaths(all, 'Board daily stuff.md'),
          ['Board Kanban/Board daily stuff.md']);
    });

    test('returns every match when the same filename exists in two folders',
        () {
      final all = [
        'Board Kanban/Board daily stuff.md',
        'Archive/Board daily stuff.md',
      ];
      expect(
          matchingLivePaths(all, 'Board daily stuff.md'),
          [
            'Board Kanban/Board daily stuff.md',
            'Archive/Board daily stuff.md',
          ]);
    });

    test('returns empty when nothing matches', () {
      expect(matchingLivePaths(['A.md', 'B.md'], 'C.md'), isEmpty);
    });
  });
}
