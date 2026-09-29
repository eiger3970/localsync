// Backups clean-up: newest "Backup <date>" kept, other LocalSync backup
// folders removed, the user's own notes and LocalSync's own files untouched.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/services/localsync_cleanup.dart';

void main() {
  test('keeps newest Backup and own notes, removes the rest', () {
    final v = Directory.systemTemp.createTempSync('vault').path;
    void w(String rel, int n) => (File('$v/$rel')..createSync(recursive: true)).writeAsStringSync('x' * n);
    w('Journal/today.md', 10);
    w('LocalSync/repo-name.txt', 5);
    w('LocalSync/Backup 202609291508/a.md', 100);
    w('LocalSync/Backup 202608011200/b.md', 200);
    w('LocalSync/Conflict Backups/c1.md', 300);
    w('LocalSync/Conflict Backups/sub/c2.md', 400);
    w('LocalSync/Vault Backup 202608201906/d.md', 50);

    final list = listBackupFolders(v);
    expect(list.map((f) => f.name).toList(),
        ['Backup 202608011200', 'Backup 202609291508', 'Conflict Backups', 'Vault Backup 202608201906']);
    expect(list.firstWhere((f) => f.name == 'Conflict Backups').files, 2);
    expect(list.firstWhere((f) => f.name == 'Conflict Backups').bytes, 700);
    expect(list.where((f) => f.keep).map((f) => f.name), ['Backup 202609291508']);

    final freed = cleanUpBackupFolders(v, list);
    expect(freed, 200 + 700 + 50);
    expect(Directory('$v/LocalSync/Backup 202609291508').existsSync(), isTrue);
    expect(Directory('$v/LocalSync/Conflict Backups').existsSync(), isFalse);
    expect(Directory('$v/LocalSync/Backup 202608011200').existsSync(), isFalse);
    expect(File('$v/LocalSync/repo-name.txt').existsSync(), isTrue);
    expect(File('$v/Journal/today.md').existsSync(), isTrue);
  });

  test('formatBytes', () {
    expect(formatBytes(24 * 1024), '24 KB');
    expect(formatBytes(155 * 1024 * 1024), '155 MB');
  });
}
