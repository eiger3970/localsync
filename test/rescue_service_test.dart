// Rescue: notes removed recently come back, older removals are left alone,
// and nothing already in the folder is overwritten.
// Needs git2dart's libgit2, shipped for x86-64 only - skipped on ARM (Pi).
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/services/rescue_service.dart';

Future<void> git(String dir, List<String> args, {String? date}) async {
  final r = await Process.run('git', args, workingDirectory: dir, environment: {
    if (date != null) 'GIT_AUTHOR_DATE': date,
    if (date != null) 'GIT_COMMITTER_DATE': date,
    'GIT_AUTHOR_NAME': 't', 'GIT_AUTHOR_EMAIL': 't@t', 'GIT_COMMITTER_NAME': 't', 'GIT_COMMITTER_EMAIL': 't@t',
  });
  if (r.exitCode != 0) throw Exception(r.stderr);
}

void main() {
  test('recent removals restored, old ones kept gone, no overwrite', skip: (Process.runSync('uname', ['-m']).stdout as String).trim() != 'x86_64' ? 'libgit2 binaries are x86-64 only' : null, () async {
    final dir = (await Directory.systemTemp.createTemp('rescue')).path;
    await git(dir, ['init', '-q']);
    for (final n in ['old.md', 'recent.md', 'clash.md', 'keep.md']) {
      File('$dir/$n').writeAsStringSync('$n text');
    }
    await git(dir, ['add', '.']);
    await git(dir, ['commit', '-qm', 'add'], date: '2026-01-01T10:00:00');
    File('$dir/old.md').deleteSync();
    await git(dir, ['commit', '-qam', 'old removal'], date: '2026-01-02T10:00:00');
    File('$dir/recent.md').deleteSync();
    File('$dir/clash.md').deleteSync();
    await git(dir, ['commit', '-qam', 'recent removal']);
    // Someone made a new clash.md since - it must not be overwritten.
    File('$dir/clash.md').writeAsStringSync('new clash text');

    final r = await rescueFolder(dir, DateTime.now().subtract(kRescueLookBack));

    expect(r.notesBack, 2);
    expect(File('$dir/recent.md').readAsStringSync(), 'recent.md text');
    expect(File('$dir/old.md').existsSync(), isFalse);
    expect(File('$dir/clash.md').readAsStringSync(), 'new clash text');
    expect(File('$dir/clash (restored).md').readAsStringSync(), 'clash.md text');
    expect(File('$dir/keep.md').readAsStringSync(), 'keep.md text');
  });
}
