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

  test('3-way: merge would put a time in the wrong place -> null, a conflict for the person (2026-11-13)', () {
    const base = '0900 a';
    const ours = '0900 a\n\nMetro thoughts.\n\n2000 c';
    const theirs = '0900 a\n\n1900 d';
    expect(mergeThreeWayLines(base, ours, theirs), isNull);
    expect(timesOutOfOrderByMerge([ours, theirs], '0900 a\n2000 c\n1900 d'), isTrue);
    expect(timesOutOfOrderByMerge(['1900 x\n2000 y', 'junk'], '1900 x\n2000 y\njunk'), isFalse);
  });
}
