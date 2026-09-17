import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/services/sync_service.dart';

void main() {
  group('neutralizeReminderTags', () {
    test('strips a live reminder-plugin tag, keeps the date/time visible', () {
      const line =
          '- [ ] Bureau des reservations will reply to SPOP email 2026-09-11 1600 (@2026-09-23 1000)';
      final result = neutralizeReminderTags(line);
      expect(result,
          '- [ ] Bureau des reservations will reply to SPOP email 2026-09-11 1600 (was due 2026-09-23 1000)');
      expect(result.contains('(@'), isFalse);
    });

    test('handles multiple tags and colon-formatted times in one file', () {
      const content = '- [ ] first (@2025-09-11 16:09)\n- [x] second (@2025-10-01 14:00)';
      final result = neutralizeReminderTags(content);
      expect(result, '- [ ] first (was due 2025-09-11 16:09)\n- [x] second (was due 2025-10-01 14:00)');
    });

    test('leaves content with no reminder tags untouched', () {
      const content = 'Just a plain note with an @mention, no date shape.';
      expect(neutralizeReminderTags(content), content);
    });
  });
}
