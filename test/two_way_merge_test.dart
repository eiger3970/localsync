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
}
