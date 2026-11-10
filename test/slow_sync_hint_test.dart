import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/widgets/slow_sync_hint.dart';

void main() {
  test('shows after 5s, lingers 15s after done', () {
    SlowSyncHint.resetForTest();
    final t = DateTime(2026, 1, 1);
    expect(SlowSyncHint.step(true, t), isFalse);
    expect(SlowSyncHint.step(true, t.add(const Duration(seconds: 5))), isTrue);
    expect(SlowSyncHint.step(false, t.add(const Duration(seconds: 6))), isTrue);
    expect(SlowSyncHint.step(false, t.add(const Duration(seconds: 20))), isTrue);
    expect(SlowSyncHint.step(false, t.add(const Duration(seconds: 22))), isFalse);
  });
  test('fast sync never shows', () {
    SlowSyncHint.resetForTest();
    final t = DateTime(2026, 1, 1);
    expect(SlowSyncHint.step(true, t), isFalse);
    expect(SlowSyncHint.step(false, t.add(const Duration(seconds: 2))), isFalse);
  });
}
