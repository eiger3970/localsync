// 2026-11-15 real loss: an untimed paragraph inside one side's new entries stopped the time sort, the merge put the
// other side's earlier entry at the bottom, the note went to Conflicts and one line was lost by the pick.
import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/services/conflict_repair.dart';

void main() {
  const base = '0900 start\n\n1120 test computer three';
  const phone = '0900 start\n\n1120 test computer three\n\n1130 test phone four\n\n\n'
      '1649 library\n\n2005 queue\n\nNo time on this line.\n\n2230 late';
  const desk = '0900 start\n\n1120 test computer three\n\n1130 test computer four';

  test('untimed paragraph moves with the entry above it, every line kept in time order', () {
    final r = mergeThreeWayLines(base, phone, desk, theirsFirst: true);
    expect(r, isNotNull);
    final lines = r!.split('\n').where((l) => l.trim().isNotEmpty).toList();
    expect(lines, [
      '0900 start',
      '1120 test computer three',
      '1130 test computer four',
      '1130 test phone four',
      '1649 library',
      '2005 queue',
      'No time on this line.',
      '2230 late',
    ]);
  });

  test('a side whose first new paragraph has no time is still not sorted', () {
    const p2 = '0900 start\n\n1120 test computer three\n\nNo time first.\n\n2230 late';
    final r = mergeThreeWayLines(base, p2, desk);
    // ours-then-theirs would put 1130 under 2230: the merge refuses (person decides), nothing silently reordered
    expect(r, isNull);
  });

  test('keeping the phone text names the computer line it removes', () {
    const phoneText = '1130 test phone four\n\n1649 library';
    const deskText = '1130 test computer four';
    expect(linesLostByKeeping(phoneText, [phoneText, deskText]), ['1130 test computer four']);
  });

  test('nothing lost when the kept text already has every line', () {
    const a = '1130 one\n\n1140 two';
    expect(linesLostByKeeping(a, [a, '1140 two']), isEmpty);
  });

  test('same note created on both devices, no line in common: both kept in time order', () {
    // 2026-11-15 real test: Nov 15th made on the computer (1130) and on the phone (1200, untimed, 1400)
    const phoneText = '1200 phone line\nNo time on this line.\n1400 phone late';
    const deskText = '1130 computer line';
    for (final r in [mergeTwoWayLines(phoneText, deskText), mergeTwoWayLines(deskText, phoneText)]) {
      expect(r, isNotNull);
      expect(r!.split('\n').where((l) => l.trim().isNotEmpty).toList(),
          ['1130 computer line', '1200 phone line', 'No time on this line.', '1400 phone late']);
    }
  });
}
