// Full copies go in the vault's hidden .localsync_backups folder (Obsidian
// never indexes it, the sync never sends it); older ones in LocalSync/ move
// there; the Backups screen always keeps them.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/services/localsync_cleanup.dart';
import 'package:localsync/services/vault_backup.dart';

void main() {
  late String v;
  void w(String rel) =>
      (File('$v/$rel')..createSync(recursive: true)).writeAsStringSync('x');

  setUp(() => v = Directory.systemTemp.createTempSync('vault').path);

  test('new full copy lands in the hidden folder, never copies itself', () async {
    w('.git/HEAD');
    w('Journal/today.md');
    w('$kFullBackupsFolder/Backup 202609291652/Journal/old.md');

    final rel = await backupVaultIfNotEmpty(v);

    expect(rel, startsWith('$kFullBackupsFolder/Backup '));
    expect(File('$v/$rel/Journal/today.md').existsSync(), isTrue);
    expect(Directory('$v/$rel/$kFullBackupsFolder').existsSync(), isFalse);
    expect(Directory('$v/$rel/.git').existsSync(), isFalse);
    expect(File('$v/.git/info/exclude').readAsStringSync(),
        contains('/$kFullBackupsFolder/'));
  });

  test('older backups move out of LocalSync, nothing else does', () {
    w('LocalSync/Backup 202609291652/a.md');
    w('LocalSync/Vault Backup 202608201906/b.md');
    w('LocalSync/Conflict Backups/c.md');
    w('LocalSync/Conflict Backups/same.md');
    w('LocalSync/Conflict Backups before 2026-09-17/d.md');
    w('LocalSync/repo-name.txt');
    w('LocalSync/Other/e.md'); // not a LocalSync backup name
    w('$kFullBackupsFolder/Backup 202609291652/older.md'); // same name
    w('$kFullBackupsFolder/Conflict Backups/same.md');

    expect(moveBackupsToHiddenFolder(v), 4);

    final h = '$v/$kFullBackupsFolder';
    expect(Directory('$v/LocalSync/Backup 202609291652').existsSync(), isFalse);
    expect(File('$h/Backup 202609291652 (2)/a.md').existsSync(), isTrue);
    expect(File('$h/Backup 202609291652/older.md').existsSync(), isTrue);
    expect(File('$h/Vault Backup 202608201906/b.md').existsSync(), isTrue);
    expect(File('$h/Conflict Backups/c.md').existsSync(), isTrue);
    expect(File('$h/Conflict Backups/same.md').existsSync(), isTrue);
    expect(File('$h/Conflict Backups/same (2).md').existsSync(), isTrue);
    expect(Directory('$v/LocalSync/Conflict Backups').existsSync(), isFalse);
    expect(File('$h/Conflict Backups before 2026-09-17/d.md').existsSync(), isTrue);
    expect(File('$v/LocalSync/repo-name.txt').existsSync(), isTrue);
    expect(File('$v/LocalSync/Other/e.md').existsSync(), isTrue);
    expect(moveBackupsToHiddenFolder(v), 0);
  });

  test('exclude line written once, existing lines kept', () {
    w('.git/info/exclude');
    File('$v/.git/info/exclude').writeAsStringSync('*.tmp');
    excludeFullBackupsFromSync(v);
    excludeFullBackupsFromSync(v);
    expect(File('$v/.git/info/exclude').readAsStringSync(),
        '*.tmp\n/$kFullBackupsFolder/\n');
  });

  test('Backups screen lists hidden copies and never cleans full ones', () {
    w('$kFullBackupsFolder/Backup 202609291652/a.md');
    w('$kFullBackupsFolder/Conflict Backups/c.md');

    final list = listBackupFolders(v);
    final hidden = list.firstWhere((f) => f.name == 'Backup 202609291652');
    expect(hidden.phoneOnly, isTrue);
    expect(hidden.keep, isTrue);

    cleanUpBackupFolders(v, list);
    expect(File('$v/$kFullBackupsFolder/Backup 202609291652/a.md').existsSync(), isTrue);
    expect(Directory('$v/$kFullBackupsFolder/Conflict Backups').existsSync(), isFalse);
  });
}
