import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/services/conflict_repair.dart';

void main() {
  test('both sides appended different lines, no ancestor: keep everything', () {
    const shared = '# 2026-11-11\n\n- 0900 coffee\n- 1000 call';
    final ours = '$shared\n- 1840 phone test';
    final theirs = '$shared\n- 1841 desktop test';
    final m = mergeTwoWayLines(ours, theirs)!;
    expect(m, contains('1840 phone test'));
    expect(m, contains('1841 desktop test'));
    expect('0900 coffee'.allMatches(m).length, 1);
    expect(m, isNot(contains('SYNC CONFLICT')));
  });

  test('3-way: both sides add timed entries in the same gap -> sorted by time (2026-11-13 diary)', () {
    const base = '0831 desktop test note.';
    const desktop = '$base\n\n1235 rude woman.\nOften looking.\n\n1247 she moved.';
    const phone = '$base\n\n1500 Sartre.\n\n2145 power pack.';
    final m = mergeThreeWayLines(base, desktop, phone)!;
    final order = ['0831', '1235', '1247', '1500', '2145'].map(m.indexOf).toList();
    expect(order.every((i) => i >= 0), isTrue);
    expect([...order]..sort(), order);
    expect(m, contains('1235 rude woman.\nOften looking.'));
    expect('0831'.allMatches(m).length, 1);
  });
  test('3-way: untimed additions keep ours then theirs', () {
    const base = 'a';
    final m = mergeThreeWayLines(base, 'a\nours line', 'a\ntheirs line')!;
    expect(m, 'a\nours line\ntheirs line');
  });
}
