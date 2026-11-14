import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/services/conflict_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 2026-11-14 owner, real Nov 14th test: the same line edited on phone and computer, KEEP BOTH chosen, and the
// Conflicts list still showed Nov 14th (the two kept 1107 lines read as a new "same time" conflict).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('KEEP BOTH on a same-line edit does not list the kept pair again', () async {
    SharedPreferences.setMockInitialValues({});
    final v = await Directory.systemTemp.createTemp('keepboth');
    try {
      await Directory('${v.path}/Journal').create();
      const desktop = '1107 test computer one, edited on computer';
      const phone = '1107 test computer one, edited on phone';
      const rest = '\n\n1109 test phone two\n\n1109 test computer two\n';
      await File('${v.path}/Journal/Nov 14th, 2026.md').writeAsString('$desktop$rest');
      final pd = await Directory('${v.path}/$kPendingFolder').create();
      final key = '${Uri.encodeComponent('Journal/Nov 14th, 2026.md')}.20261114114900';
      await File('${pd.path}/$key.desktop.md').writeAsString('$desktop\n');
      await File('${pd.path}/$key.phone.md').writeAsString('$phone\n');

      final found = await scanForConflicts(v.path);
      expect(found.length, 1);
      await mergeConflictKeepingBoth(v.path, found.single);
      final text = await File('${v.path}/Journal/Nov 14th, 2026.md').readAsString();
      expect(text.contains('edited on phone'), isTrue);
      expect(text.contains('edited on computer'), isTrue);
      expect(await scanForConflicts(v.path), isEmpty);
    } finally {
      await v.delete(recursive: true);
    }
  });
}
