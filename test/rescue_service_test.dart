// Rescue: the last big disappearance (20+ notes in one sync) comes back,
// a single ordinary deletion and anything in a LocalSync folder do not,
// and nothing already in the folder is overwritten.
// Needs git2dart's libgit2, shipped for x86-64 only - skipped on ARM (Pi).
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/services/rescue_service.dart';

Future<void> git(String dir, List<String> args) async {
  final r = await Process.run('git', args, workingDirectory: dir, environment: {
    'GIT_AUTHOR_NAME': 't', 'GIT_AUTHOR_EMAIL': 't@t', 'GIT_COMMITTER_NAME': 't', 'GIT_COMMITTER_EMAIL': 't@t',
  });
  if (r.exitCode != 0) throw Exception(r.stderr);
}

void main() {
  test('mass disappearance back, ordinary deletion and LocalSync copies not', skip: (Process.runSync('uname', ['-m']).stdout as String).trim() != 'x86_64' ? 'libgit2 binaries are x86-64 only' : null, () async {
    final dir = (await Directory.systemTemp.createTemp('rescue')).path;
    await git(dir, ['init', '-q']);
    for (var i = 0; i < 25; i++) { File('$dir/n$i.md').writeAsStringSync('note $i'); }
    File('$dir/single.md').writeAsStringSync('single');
    File('$dir/LocalSync/Conflict Backups/c.md')..createSync(recursive: true)..writeAsStringSync('copy');
    await git(dir, ['add', '.']);
    await git(dir, ['commit', '-qm', 'add']);
    File('$dir/single.md').deleteSync();
    File('$dir/LocalSync/Conflict Backups/c.md').deleteSync();
    await git(dir, ['commit', '-qam', 'ordinary']);
    for (var i = 0; i < 25; i++) { File('$dir/n$i.md').deleteSync(); }
    await git(dir, ['commit', '-qam', 'wipe']);

    final r = await rescueFolder(dir, DateTime.now().subtract(kRescueLookBack));

    expect(r.notesBack, 25);
    expect(File('$dir/n0.md').readAsStringSync(), 'note 0');
    expect(File('$dir/single.md').existsSync(), isFalse);
    expect(File('$dir/LocalSync/Conflict Backups/c.md').existsSync(), isFalse);
  });
}
