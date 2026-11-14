import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/services/sync_service.dart';

// 2026-11-14 owner's real test: computer edit pulled at 12:41, Obsidian on the phone then saved its older copy at
// 12:43 and the computer's edit vanished. isStaleSave spots that save; git then merges it (mergeStaleSavesWithGit).
void main() {
  const base = '1107 one\n\n1109 test phone two\n\n1109 test computer two\n';
  const pulled = '1107 one\n\n1109 test phone two, edited on computer\n\n1109 test computer two\n';
  const staleSave = '1107 one\n\n1109 test phone two, edited on phone\n\n1109 test computer two\n';

  test('Obsidian saved over a pulled edit: stale', () {
    expect(isStaleSave(base, staleSave, pulled), isTrue);
  });
  test('old copy written back with no typing: stale', () {
    expect(isStaleSave(base, base, pulled), isTrue);
  });
  test('edit typed on top of the pulled text: not stale', () {
    expect(isStaleSave(base, '$pulled\n1130 new\n', pulled), isFalse);
  });
  test('nothing typed after the pull: not stale', () {
    expect(isStaleSave(base, pulled, pulled), isFalse);
  });
  test('pull only removed lines: not stale', () {
    expect(isStaleSave(base, staleSave, '1107 one\n'), isFalse);
  });
}
