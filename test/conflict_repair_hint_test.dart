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
}
