import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/services/conflict_repair.dart';
void main() {
  test('2026-11-14 real diary: the same edit on both sides plus each side adding entries -> merged in time order', () {
    const base = '0626 started. He hopped back in bed at 0629 ';
    const phone = '0626 started. He hopped back in bed at 0629.\n\n1500 test phone one\n\n2145 test phone two';
    const desk = '0626 started. He hopped back in bed at 0629.\n\n1235 test desktop one\n \n1247 test desktop two';
    final m = mergeThreeWayLines(base, phone, desk)!;
    final order = ['0629.', '1235', '1247', '1500', '2145'].map(m.indexOf).toList();
    expect(order.every((i) => i >= 0), isTrue);
    expect([...order]..sort(), order);
    expect('0629.'.allMatches(m).length, 1);
    // both rewrote the same line DIFFERENTLY: still a conflict
    expect(mergeThreeWayLines('a', 'b', 'c'), isNull);
  });
}
