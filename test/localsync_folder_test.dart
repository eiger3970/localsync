// Pure Dart/file-I/O layer, no git2dart - runs on this machine.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/services/localsync_folder.dart';
import 'package:localsync/services/vault_backup.dart';

void main() {
  late Directory vault;

  setUp(() {
    vault = Directory.systemTemp.createTempSync('localsync_folder_test_');
  });

  tearDown(() => vault.deleteSync(recursive: true));

  group('sanitizeLocalSyncFolder', () {
    test('keeps a normal nested path', () {
      expect(sanitizeLocalSyncFolder('Projects/LocalSync'), 'Projects/LocalSync');
    });
    test('trims spaces, slashes and backslashes', () {
      expect(sanitizeLocalSyncFolder('  Projects\\LocalSync/  '),
          'Projects/LocalSync');
      expect(sanitizeLocalSyncFolder('Projects//LocalSync'), 'Projects/LocalSync');
    });
    test('rejects anything leaving the vault or hidden', () {
      for (final bad in ['', '   ', '/abs/path', '../outside', 'a/../b',
          '.git', 'Projects/.hidden', '.']) {
        expect(sanitizeLocalSyncFolder(bad), isNull, reason: bad);
      }
    });
  });

  group('localSyncFolder', () {
    test('defaults when no file exists', () {
      expect(localSyncFolder(vault.path), kLocalSyncFolderName);
      expect(localSyncFolders(vault.path), [kLocalSyncFolderName]);
    });

    test('reads the configured folder and keeps the default as legacy', () {
      File('${vault.path}/$kLocalSyncFolderFile')
          .writeAsStringSync('Projects/LocalSync\n');
      expect(localSyncFolder(vault.path), 'Projects/LocalSync');
      expect(localSyncFolders(vault.path),
          ['Projects/LocalSync', kLocalSyncFolderName]);
      expect(conflictBackupsDir(vault.path),
          '${vault.path}/Projects/LocalSync/Conflict Backups');
      expect(lastKnownLocalSyncFolder, 'Projects/LocalSync');
    });

    test('an unsafe value in the file falls back to the default', () {
      File('${vault.path}/$kLocalSyncFolderFile').writeAsStringSync('../x\n');
      expect(localSyncFolder(vault.path), kLocalSyncFolderName);
    });

    test('setLocalSyncFolder writes a clean value, refuses a bad one', () {
      expect(setLocalSyncFolder(vault.path, ' Projects/LocalSync/ '),
          'Projects/LocalSync');
      expect(File('${vault.path}/$kLocalSyncFolderFile').readAsStringSync(),
          'Projects/LocalSync\n');
      expect(setLocalSyncFolder(vault.path, '../escape'), isNull);
      expect(localSyncFolder(vault.path), 'Projects/LocalSync');
    });
  });

  test('isInLocalSyncFolder matches the folder and below, nothing else', () {
    final folders = ['Projects/LocalSync', 'LocalSync'];
    expect(isInLocalSyncFolder('Projects/LocalSync/Conflict Backups/a.md', folders), isTrue);
    expect(isInLocalSyncFolder('LocalSync/repo-name.txt', folders), isTrue);
    expect(isInLocalSyncFolder('Projects/LocalSync.md', folders), isFalse);
    expect(isInLocalSyncFolder('Projects/Other/a.md', folders), isFalse);
  });

  test('readRepoName prefers the configured folder, falls back to default', () {
    Directory('${vault.path}/LocalSync').createSync();
    File('${vault.path}/LocalSync/repo-name.txt').writeAsStringSync('Old\n');
    expect(readRepoName(vault.path), 'Old');
    setLocalSyncFolder(vault.path, 'Projects/LocalSync');
    expect(readRepoName(vault.path), 'Old');
    Directory('${vault.path}/Projects/LocalSync').createSync(recursive: true);
    File('${vault.path}/Projects/LocalSync/repo-name.txt').writeAsStringSync('New\n');
    expect(readRepoName(vault.path), 'New');
  });

  test('vault backup skips the nested folder but keeps its siblings', () async {
    setLocalSyncFolder(vault.path, 'Projects/LocalSync');
    Directory('${vault.path}/Projects/LocalSync/Conflict Backups')
        .createSync(recursive: true);
    File('${vault.path}/Projects/LocalSync/Conflict Backups/old.md')
        .writeAsStringSync('old backup');
    File('${vault.path}/Projects/plan.md').writeAsStringSync('real note');
    File('${vault.path}/note.md').writeAsStringSync('top note');

    expect(await backupVaultIfNotEmpty(vault.path), isTrue);

    final backups = Directory('${vault.path}/Projects/LocalSync')
        .listSync()
        .whereType<Directory>()
        .where((d) => d.path.contains('Vault Backup '))
        .toList();
    expect(backups, hasLength(1));
    final b = backups.single.path;
    expect(File('$b/note.md').existsSync(), isTrue);
    expect(File('$b/Projects/plan.md').existsSync(), isTrue,
        reason: 'real notes next to the LocalSync folder must be backed up');
    expect(Directory('$b/Projects/LocalSync').existsSync(), isFalse,
        reason: 'the backup must not copy LocalSync into itself');
  });
}
