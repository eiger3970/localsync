import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/services/conflict_repair.dart';

void main() {
  group('allHaveLeadingTime', () {
    test('true when every body starts with a bare HHMM time', () {
      expect(
          allHaveLeadingTime([
            '2105 salad Caucasian Swiss? Gave me a hard time.',
            '0715 I left early for the appointment.',
          ]),
          isTrue);
    });

    test('false when any body has no leading time', () {
      expect(
          allHaveLeadingTime([
            '2105 salad Caucasian Swiss? Gave me a hard time.',
            'Fixed the pairing screen this morning.',
          ]),
          isFalse);
    });

    test('false for an empty list - never guesses on nothing', () {
      expect(allHaveLeadingTime([]), isFalse);
    });

    test('false when neither side has a leading time', () {
      expect(
          allHaveLeadingTime([
            'Fixed the pairing screen this morning.',
            'Emailed about the domicile case this afternoon.',
          ]),
          isFalse);
    });
  });

  group('oneContainsTheOther', () {
    test('true when the longer side contains the shorter one verbatim', () {
      expect(
          oneContainsTheOther(
              'Fixed the pairing screen this morning.',
              'Fixed the pairing screen this morning. Also pushed the '
                  'follow-up fix.'),
          isTrue);
    });

    test('true regardless of argument order', () {
      expect(
          oneContainsTheOther(
              'Fixed the pairing screen this morning. Also pushed the '
                  'follow-up fix.',
              'Fixed the pairing screen this morning.'),
          isTrue);
    });

    test('false for genuinely different content, even if similar length',
        () {
      expect(
          oneContainsTheOther(
              'Fixed the pairing screen this morning.',
              'Emailed about the domicile case this morning.'),
          isFalse);
    });

    test('false when either side is empty - never claims containment on '
        'nothing', () {
      expect(oneContainsTheOther('', 'Real content here.'), isFalse);
      expect(oneContainsTheOther('Real content here.', ''), isFalse);
      expect(oneContainsTheOther('', ''), isFalse);
    });
  });

  group('oneSideSuspiciouslyShort', () {
    test('true for a tiny side next to a substantial one', () {
      expect(
          oneSideSuspiciouslyShort(
              'ok',
              'Fixed the pairing screen this morning after a long chase '
                  'through the logs.'),
          isTrue);
    });

    test('false when both sides are genuinely short one-liners', () {
      expect(oneSideSuspiciouslyShort('ok', 'done'), isFalse);
    });

    test('false when both sides are substantial, even if lengths differ '
        'somewhat', () {
      expect(
          oneSideSuspiciouslyShort(
              'Fixed the pairing screen this morning after a long chase.',
              'Fixed the pairing screen this morning after a long chase '
                  'through every log file on the desktop side.'),
          isFalse);
    });

    test('false for two empty sides', () {
      expect(oneSideSuspiciouslyShort('', ''), isFalse);
    });
  });

  group('hasDuplicateParagraph', () {
    test('true when the same paragraph appears twice - the real Sep 7th '
        'shape', () {
      expect(
          hasDuplicateParagraph(
              '# Tonight\n\n'
              '1. Hand him your phone and open the CV generator.\n\n'
              '# Tonight\n\n'
              '1. Hand him your phone and open the CV generator.\n'),
          isTrue);
    });

    test('false when paragraphs genuinely differ', () {
      expect(
          hasDuplicateParagraph(
              'First paragraph with real content here.\n\n'
              'A completely different second paragraph.\n'),
          isFalse);
    });

    test('false for a single paragraph - nothing to duplicate against', () {
      expect(hasDuplicateParagraph('Just one paragraph, on its own.'),
          isFalse);
    });

    test('ignores very short repeated lines - not a real signal', () {
      expect(hasDuplicateParagraph('ok\n\nok\n\nok'), isFalse);
    });
  });
}
