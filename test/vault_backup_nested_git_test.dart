// A backup never copies .git, and a .git already copied into a LocalSync
// backup is removed - the vault's own .git at its root is never touched.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/services/vault_backup.dart';

void main() {
  test('no nested .git in LocalSync backups', () async {
    final v = Directory.systemTemp.createTempSync('vault').path;
    void w(String rel) => (File('$v/$rel')..createSync(recursive: true)).writeAsStringSync('x');
    w('.git/HEAD');
    w('note.md');
    w('LocalSync/Backup 202609291652/.git/HEAD'); // the bad copy from before
    w('LocalSync/Backup 202609291652/note.md');

    final rel = await backupVaultIfNotEmpty(v);

    expect(Directory('$v/.git').existsSync(), isTrue);
    expect(Directory('$v/LocalSync/Backup 202609291652/.git').existsSync(), isFalse);
    expect(File('$v/LocalSync/Backup 202609291652/note.md').existsSync(), isTrue);
    expect(Directory('$v/$rel/.git').existsSync(), isFalse);
    expect(File('$v/$rel/note.md').existsSync(), isTrue);
  });
}
