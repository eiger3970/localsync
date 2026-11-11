import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/services/conflict_scanner.dart';

void main() {
  test('pending pair from the desktop shows as a normal conflict and settles', () async {
    final v = await Directory.systemTemp.createTemp('pend');
    try {
      await Directory('${v.path}/Journal').create();
      const desktop = '0803 backpack missing selfie stick.\n\n1400 I collected 2 letters.';
      const phone = '0803 unpacking backpack, selfie stick stolen.\n\n1400 I collected 2 letters.\n\n2030 old thug pushed in.';
      await File('${v.path}/Journal/Nov 10th, 2026.md').writeAsString('# Nov 10\n$desktop\n\nafter\n');
      final pd = await Directory('${v.path}/$kPendingFolder').create();
      final key = '${Uri.encodeComponent('Journal/Nov 10th, 2026.md')}.20261110210000';
      await File('${pd.path}/$key.desktop.md').writeAsString('$desktop\n');
      await File('${pd.path}/$key.phone.md').writeAsString('$phone\n');

      final found = await scanForConflicts(v.path);
      expect(found.length, 1);
      final e = found.single;
      expect(e.filePath, 'Journal/Nov 10th, 2026.md');
      expect(e.versions[0].body, phone);
      expect(e.versions[1].body, desktop);
      final text = await File('${v.path}/Journal/Nov 10th, 2026.md').readAsString();
      expect(text.substring(e.matchStart, e.matchEnd), desktop);

      await settlePendingConflict(e);
      expect(await scanForConflicts(v.path), isEmpty);
      expect(File('${pd.path}/resolved/$key.phone.md').existsSync(), isTrue);
    } finally {
      await v.delete(recursive: true);
    }
  });
}
