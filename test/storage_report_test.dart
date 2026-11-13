import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:git2dart/git2dart.dart';
import 'package:localsync/services/storage_report.dart';

void main() {
  test('compactGitStoreSync packs loose objects and keeps every commit readable', () {
    final dir = Directory.systemTemp.createTempSync('compact_');
    final path = dir.path;
    void git(List<String> a) {
      final r = Process.runSync('git', ['-C', path, ...a]);
      if (r.exitCode != 0) throw StateError(r.stderr.toString());
    }

    git(['init', '-q']);
    git(['config', 'user.email', 't@t']);
    git(['config', 'user.name', 't']);
    for (var i = 0; i < 40; i++) {
      File('$path/note.md').writeAsStringSync('line\n' * 200 + 'change $i\n');
      File('$path/n$i.md').writeAsStringSync('note $i\n');
      git(['add', '-A']);
      git(['commit', '-qm', 'c$i']);
    }
    final (looseBefore, _) = looseObjects('$path/.git');
    expect(looseBefore, greaterThan(100));

    final r = compactGitStoreSync(path, minLoose: 50);
    expect(r, isNotNull);
    expect(r!.afterBytes, lessThan(r.beforeBytes));
    expect(looseObjects('$path/.git').$1, 0);

    // git itself still reads every commit and file.
    final fsck = Process.runSync('git', ['-C', path, 'fsck', '--full']);
    expect(fsck.exitCode, 0, reason: fsck.stderr.toString());
    final log = Process.runSync('git', ['-C', path, 'log', '--oneline']);
    expect(log.stdout.toString().trim().split('\n').length, 40);
    final repo = Repository.open(path);
    expect(repo.head.target, isNotNull);
    repo.free();

    // Below the threshold: nothing to do.
    expect(compactGitStoreSync(path, minLoose: 50), isNull);
    dir.deleteSync(recursive: true);
  });

  test('storageReport lists hidden folders and backups by name', () async {
    final dir = Directory.systemTemp.createTempSync('storage_');
    Directory('${dir.path}/.localsync_backups/Backup 1').createSync(recursive: true);
    File('${dir.path}/.localsync_backups/Backup 1/a.md').writeAsStringSync('x' * 5000);
    File('${dir.path}/Daily/x.md')
      ..createSync(recursive: true)
      ..writeAsStringSync('hello');
    final s = await storageReport(dir.path);
    expect(s, contains('.localsync_backups'));
    expect(s, contains('Backup 1'));
    expect(s, contains('notes and attachments'));
    expect(s, isNot(contains('x.md')));
    dir.deleteSync(recursive: true);
  });
}
