import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/services/conflict_repair.dart';

// 2026-11-14 owner's real test: computer typed "1109 test computer two" first, phone "1109 test phone two" after.
// Same journal time on both sides -> the side that saved its change earlier goes first.
void main() {
  const base = '1107 test computer one';
  const phone = '1107 test computer one\n\n1109 test phone two';
  const desk = '1107 test computer one\n\n1109 test computer two';

  test('phone merging, computer saved earlier (theirsFirst) -> computer entry first', () {
    final m = mergeThreeWayLines(base, phone, desk, theirsFirst: true)!;
    expect(m.indexOf('1109 test computer two') < m.indexOf('1109 test phone two'), isTrue, reason: m);
    expect(m.indexOf('1107') < m.indexOf('1109'), isTrue);
  });

  test('phone merging, phone saved earlier -> phone entry first', () {
    final m = mergeThreeWayLines(base, phone, desk)!;
    expect(m.indexOf('1109 test phone two') < m.indexOf('1109 test computer two'), isTrue, reason: m);
  });

  test('different times still sort by time whatever side saved first', () {
    const p2 = '1107 test computer one\n\n1105 early phone';
    final m = mergeThreeWayLines(base, p2, desk, theirsFirst: true)!;
    expect(m.indexOf('1105') < m.indexOf('1109'), isTrue, reason: m);
  });

  test('no common ancestor (two-way) follows the same rule', () {
    final m = mergeTwoWayLines(phone, desk, theirsFirst: true)!;
    expect(m.indexOf('1109 test computer two') < m.indexOf('1109 test phone two'), isTrue, reason: m);
  });
}
