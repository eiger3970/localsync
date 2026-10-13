import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/services/sync_service.dart';

void main() {
  test('OK and empty status show nothing', () {
    expect(desktopStatusMessage('OK\t2026-10-13 14:05\n'), isNull);
    expect(desktopStatusMessage(''), isNull);
  });
  test('stuck index.lock gets the plain explanation', () {
    final m = desktopStatusMessage(
        "FAIL\t2026-10-13 14:05\tUnable to create '/v/.git/index.lock': File exists.\n")!;
    expect(m, startsWith('Desktop sync stopped 2026-10-13 14:05\n'));
    expect(m, contains('git lock file was stuck'));
    expect(m, endsWith('LocalSync main screen -> ⋮ -> Desktop sync'));
  });
  test('other reasons are shown as git gave them', () {
    expect(desktopStatusMessage('FAIL\t2026-10-13 14:05\tBare repo not found: x.git')!,
        contains('Bare repo not found: x.git'));
  });
}
