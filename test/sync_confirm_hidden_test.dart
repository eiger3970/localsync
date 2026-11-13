import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/widgets/sync_confirm_dialog.dart';

void main() {
  test('hidden folders are settings, not notes', () {
    expect(isHiddenPath('.obsidian-backup/app.json'), isTrue);
    expect(isHiddenPath('Daily/.trash/old.md'), isTrue);
    expect(isHiddenPath('Daily/Nov 13th, 2026.md'), isFalse);
    expect(isHiddenPath('image.png'), isFalse);
  });
}
