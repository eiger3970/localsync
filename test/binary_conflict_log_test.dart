// Pure Dart/file-I/O layer, no git2dart involved - unlike
// binary_conflict_test.dart, this actually runs on this machine (see
// that file's own header for why the git2dart-dependent test can't).
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/services/binary_conflict_log.dart';
import 'package:localsync/services/vault_backup.dart';

void main() {
  late Directory vault;

  setUp(() {
    vault = Directory.systemTemp.createTempSync('binary_conflict_log_test_');
    Directory('${vault.path}/$kLocalSyncFolderName/Conflict Backups')
        .createSync(recursive: true);
  });

  tearDown(() => vault.deleteSync(recursive: true));

  BinaryConflictLogEntry _sample({String path = 'photo.jpg'}) {
    final backupDir = '${vault.path}/$kLocalSyncFolderName/Conflict Backups';
    File('$backupDir/photo - yours - 202608271200.jpg')
        .writeAsBytesSync([1, 2, 3]);
    File('$backupDir/photo - desktop - 202608271200.jpg')
        .writeAsBytesSync([4, 5, 6]);
    return BinaryConflictLogEntry(
      path: path,
      keptBackupName: 'photo - yours - 202608271200.jpg',
      otherBackupName: 'photo - desktop - 202608271200.jpg',
      otherLabel: 'desktop',
      when: '202608271200',
    );
  }

  group('binary conflict log', () {
    test('starts empty for a vault with no conflicts', () {
      expect(scanBinaryConflictLog(vault.path), isEmpty);
    });

    test('appended entries round-trip through the log', () {
      final entry = _sample();
      appendBinaryConflictLogEntry(vault.path, entry);
      final scanned = scanBinaryConflictLog(vault.path);
      expect(scanned, hasLength(1));
      expect(scanned.single.path, 'photo.jpg');
      expect(scanned.single.otherLabel, 'desktop');
    });

    test('multiple entries accumulate, not overwrite', () {
      appendBinaryConflictLogEntry(vault.path, _sample(path: 'a.jpg'));
      appendBinaryConflictLogEntry(vault.path, _sample(path: 'b.jpg'));
      expect(scanBinaryConflictLog(vault.path).map((e) => e.path),
          ['a.jpg', 'b.jpg']);
    });

    test('swapBinaryConflict writes the other side into the live file and clears the entry',
        () {
      File('${vault.path}/photo.jpg').writeAsBytesSync([1, 2, 3]); // "ours"
      final entry = _sample();
      appendBinaryConflictLogEntry(vault.path, entry);

      swapBinaryConflict(vault.path, entry);

      expect(File('${vault.path}/photo.jpg').readAsBytesSync(), [4, 5, 6]);
      expect(scanBinaryConflictLog(vault.path), isEmpty);
      // Original "ours" is still recoverable - swap never deletes the
      // backup it displaced, same convention as the markdown Undo.
      expect(
          File('${vault.path}/$kLocalSyncFolderName/Conflict Backups/'
                  'photo - yours - 202608271200.jpg')
              .existsSync(),
          isTrue);
    });

    test('dismissBinaryConflictLogEntry clears the entry without touching the live file',
        () {
      File('${vault.path}/photo.jpg').writeAsBytesSync([9, 9, 9]);
      final entry = _sample();
      appendBinaryConflictLogEntry(vault.path, entry);

      dismissBinaryConflictLogEntry(vault.path, entry);

      expect(scanBinaryConflictLog(vault.path), isEmpty);
      expect(File('${vault.path}/photo.jpg').readAsBytesSync(), [9, 9, 9]);
    });

    test('a corrupt log file is treated as empty, not a crash', () {
      File('${vault.path}/$kLocalSyncFolderName/Conflict Backups/binary_conflicts.json')
          .writeAsStringSync('{not valid json');
      expect(scanBinaryConflictLog(vault.path), isEmpty);
    });
  });
}
