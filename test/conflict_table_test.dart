import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/services/conflict_table.dart';

void main() {
  test('real 2026-11-10 diary: phone vs desktop side by side', () {
    const phone = '0803 backpack missing selfie stick.\n\n'
        'I left back pack in 31C.\n\n'
        '1400 I collected 2 letters from Riponne.\n\n'
        '2120 I reported stolen items.';
    const desktop = '0803 unpacking backpack, selfie stick stolen.\n\n'
        '1400 I collected 2 letters from Riponne.\n\n'
        '2030 old thug pushed in | Clara stopped him.';
    final t = conflictTable(phone, desktop);
    // ignore: avoid_print
    print(t);
    expect(t.startsWith('| Phone | Desktop |'), isTrue);
    expect(t.contains('1400 I collected 2 letters from Riponne. | 1400 I collected 2 letters from Riponne.'), isTrue);
    expect(t.contains(r'\|'), isTrue);
    // every line from both sides survives
    for (final s in ['0803 backpack missing', 'I left back pack', '2120 I reported', '0803 unpacking', '2030 old thug']) {
      expect(t.contains(s), isTrue, reason: s);
    }
    expect(conflictTable('same', 'same'), '');
  });
}
