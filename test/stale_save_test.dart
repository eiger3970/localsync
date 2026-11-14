import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/services/sync_service.dart';

// 2026-11-14 owner's real test: computer edit pulled at 12:41, Obsidian on the phone then saved its older copy at
// 12:43 and the computer's edit vanished.
void main() {
  const base = '1107 one\n\n1109 test phone two\n\n1109 test computer two\n';
  const pulled = '1107 one\n\n1109 test phone two, edited on computer\n\n1109 test computer two\n';
  const staleSave = '1107 one\n\n1109 test phone two, edited on phone\n\n1109 test computer two\n';

  test('Obsidian saved over a pulled edit: both edits kept', () {
    final m = staleSaveMerge(base, staleSave, pulled)!;
    expect(m.contains('edited on computer'), isTrue, reason: m);
    expect(m.contains('edited on phone'), isTrue, reason: m);
    expect(m.contains('1109 test computer two'), isTrue);
    // computer's edit (saved first) right before the phone's, both before the untouched 1109 line
    expect(m.indexOf('edited on computer') < m.indexOf('edited on phone'), isTrue, reason: m);
    expect(m.indexOf('edited on phone') < m.indexOf('1109 test computer two'), isTrue, reason: m);
  });

  test('edit typed on top of the pulled text: committed as typed', () {
    const builtOn = '1107 one\n\n1109 test phone two, edited on computer\n\n1109 test computer two\n\n1130 new\n';
    expect(staleSaveMerge(base, builtOn, pulled), isNull);
  });

  test('old copy written back with no typing: pulled text restored', () {
    expect(staleSaveMerge(base, base, pulled), pulled);
  });

  test('pull only removed lines: nothing to rescue', () {
    expect(staleSaveMerge(base, staleSave, '1107 one\n'), isNull);
  });

  test('added lines never dropped', () {
    const p2 = '1107 one\n\n1200 lunch\n\n1109 test phone two\n\n1109 test computer two\n';
    const s2 = '1107 one\n\n1109 test phone two\n\n1109 test computer two\n\n1300 walk\n';
    final m = staleSaveMerge(base, s2, p2)!;
    expect(m.contains('1200 lunch'), isTrue, reason: m);
    expect(m.contains('1300 walk'), isTrue, reason: m);
  });
}
