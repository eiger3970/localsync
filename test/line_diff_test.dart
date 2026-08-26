import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/services/line_diff.dart';

void main() {
  group('mergeHunks', () {
    test('identical paragraphs produce only same hunks', () {
      const text = 'First paragraph.\n\nSecond paragraph.';
      final hunks = mergeHunks(text, text);
      expect(hunks, everyElement(predicate((MergeHunk h) => h.op == HunkOp.same)));
      expect(hunks.map((h) => h.ours).join('\n\n'), text);
    });

    test('a differing middle paragraph becomes one conflict hunk, '
        'unchanged paragraphs around it stay same', () {
      final ours = 'Intro line.\n\nOurs middle.\n\nShared ending.';
      final theirs = 'Intro line.\n\nTheirs middle.\n\nShared ending.';
      final hunks = mergeHunks(ours, theirs);
      expect(hunks.length, 3);
      expect(hunks[0].op, HunkOp.same);
      expect(hunks[0].ours, 'Intro line.');
      expect(hunks[1].op, HunkOp.conflict);
      expect(hunks[1].ours, 'Ours middle.');
      expect(hunks[1].theirs, 'Theirs middle.');
      expect(hunks[2].op, HunkOp.same);
      expect(hunks[2].ours, 'Shared ending.');
    });

    test('an added paragraph on one side only is its own conflict hunk '
        '(ours empty, theirs has it)', () {
      final ours = 'Shared.';
      final theirs = 'Shared.\n\nNew from theirs.';
      final hunks = mergeHunks(ours, theirs);
      expect(hunks.length, 2);
      expect(hunks[0].op, HunkOp.same);
      expect(hunks[1].op, HunkOp.conflict);
      expect(hunks[1].ours, '');
      expect(hunks[1].theirs, 'New from theirs.');
    });

    test('one differing sentence inside an otherwise-identical paragraph '
        'refines to just that sentence, not the whole paragraph', () {
      final ours = 'First sentence stays the same. Called the bank, no '
          'progress. Third sentence also unchanged.';
      final theirs = 'First sentence stays the same. Emailed about the '
          'case instead. Third sentence also unchanged.';
      final hunks = mergeHunks(ours, theirs);
      expect(hunks.length, 3);
      expect(hunks[0].op, HunkOp.same);
      expect(hunks[0].ours, 'First sentence stays the same. ');
      expect(hunks[1].op, HunkOp.conflict);
      expect(hunks[1].ours, 'Called the bank, no progress. ');
      expect(hunks[1].theirs, 'Emailed about the case instead. ');
      expect(hunks[2].op, HunkOp.same);
      expect(hunks[2].ours, 'Third sentence also unchanged.');
      // every sentence hunk shares one paragraphGroup - no stray
      // paragraph break gets inserted between them on compose.
      expect(hunks.map((h) => h.paragraphGroup).toSet(), {0});
      expect(composeMerge(hunks, {}), ours);
      expect(composeMerge(hunks, {1}), theirs);
    });

    test('an unrelated paragraph elsewhere stays a separate hunk group, '
        'still gets a real paragraph break on compose', () {
      final ours = 'Para one sentence A. Para one sentence B.\n\nPara two.';
      final theirs =
          'Para one sentence A. Changed sentence B.\n\nPara two.';
      final hunks = mergeHunks(ours, theirs);
      expect(composeMerge(hunks, {}), ours);
      expect(hunks.last.op, HunkOp.same);
      expect(hunks.last.ours, 'Para two.');
      expect(hunks.first.paragraphGroup, isNot(hunks.last.paragraphGroup));
    });
  });

  group('composeMerge', () {
    test('defaults every conflict hunk to ours when nothing is chosen '
        '- never silently drops to blank', () {
      final ours = 'A.\n\nOurs B.\n\nC.';
      final theirs = 'A.\n\nTheirs B.\n\nC.';
      final hunks = mergeHunks(ours, theirs);
      expect(composeMerge(hunks, {}), ours);
    });

    test('picking theirs for a specific hunk index swaps just that piece', () {
      final ours = 'A.\n\nOurs B.\n\nC.';
      final theirs = 'A.\n\nTheirs B.\n\nC.';
      final hunks = mergeHunks(ours, theirs);
      final conflictIndex = hunks.indexWhere((h) => h.op == HunkOp.conflict);
      final merged = composeMerge(hunks, {conflictIndex});
      expect(merged, 'A.\n\nTheirs B.\n\nC.');
    });
  });
}
