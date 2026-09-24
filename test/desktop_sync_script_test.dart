// The app installs the desktop sync script from kDesktopSyncScript (a
// generated constant - see tool/gen_desktop_script.py for why it isn't a
// bundled asset). This fails the moment the .sh is edited without
// re-running the generator, so the phone can never install a stale copy.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/generated/desktop_sync_script.dart';

void main() {
  test('generated script matches desktop/localsync_sync.sh exactly', () {
    expect(kDesktopSyncScript,
        File('desktop/localsync_sync.sh').readAsStringSync(),
        reason: 'run: python3 tool/gen_desktop_script.py');
  });
}
