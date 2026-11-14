import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:git2dart/git2dart.dart' as git;
import 'package:localsync/services/conflict_scanner.dart';
import 'package:localsync/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 2026-11-14 owner's real test, with real git: the pull brought the computer's edit, then Obsidian on the phone saved
// its older copy over it. Needs a libgit2 for this machine (LD_LIBRARY_PATH on the Raspberry Pi).
String _git(String dir, List<String> args) {
  final r = Process.runSync('git', ['-C', dir, ...args]);
  if (r.exitCode != 0) throw Exception('git ${args.join(' ')}: ${r.stderr}');
  return (r.stdout as String).trim();
}

Future<Directory> _repo(String prior, String pulled) async {
  final d = await Directory.systemTemp.createTemp('latesave');
  _git(d.path, ['init', '-q', '-b', 'main']);
  _git(d.path, ['config', 'user.email', 't@t']);
  _git(d.path, ['config', 'user.name', 'desktop obsidian']);
  await Directory('${d.path}/Journal').create();
  File('${d.path}/Journal/Nov 14th.md').writeAsStringSync(prior);
  _git(d.path, ['add', '.']);
  _git(d.path, ['commit', '-qm', 'prior']);
  final p = _git(d.path, ['rev-parse', 'HEAD']);
  File('${d.path}/Journal/Nov 14th.md').writeAsStringSync(pulled);
  _git(d.path, ['commit', '-qam', 'Desktop sync']);
  // what the phone's pull records
  File('${d.path}/.git/localsync_pre_pull_head').writeAsStringSync('$p\n${DateTime.now().millisecondsSinceEpoch}\n');
  return d;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    git.Libgit2.ownerValidation = false;
  });

  test('same line edited: git conflict, computer line in the note, phone line in Conflicts, nothing lost', () async {
    const prior = '1107 one\n\n1109 test phone two\n\n1109 test computer two\n';
    const pulled = '1107 one\n\n1109 test phone two, edited on computer\n\n1109 test computer two\n';
    const late = '1107 one\n\n1109 test phone two, edited on phone\n\n1109 test computer two\n';
    final d = await _repo(prior, pulled);
    try {
      File('${d.path}/Journal/Nov 14th.md').writeAsStringSync(late);
      final repo = git.Repository.open(d.path);
      expect(commitDirtyTree(repo, '202611141243', 'iPhone'), isTrue);
      final note = File('${d.path}/Journal/Nov 14th.md').readAsStringSync();
      expect(note.contains('edited on computer'), isTrue, reason: note);
      expect(note.contains('<<<<<<<'), isFalse);
      final found = await scanForConflicts(d.path);
      expect(found.length, 1);
      final bodies = found.single.versions.map((v) => v.body).join('|');
      expect(bodies.contains('edited on phone'), isTrue, reason: bodies);
      expect(bodies.contains('edited on computer'), isTrue, reason: bodies);
      // a real git merge: two parents, Obsidian's save is one of them
      final parents = _git(d.path, ['log', '-1', '--format=%P']).split(' ');
      expect(parents.length, 2);
      expect(_git(d.path, ['show', '${parents[1]}:Journal/Nov 14th.md']).contains('edited on phone'), isTrue);
      expect(_git(d.path, ['status', '--porcelain', '--', 'Journal']), isEmpty);
      repo.free();
    } finally {
      await d.delete(recursive: true);
    }
  });

  test('different lines edited: git merges both, no conflict', () async {
    const prior = '1107 one\n\n1109 two\n\n1110 three\n';
    const pulled = '1107 one, computer\n\n1109 two\n\n1110 three\n';
    const late = '1107 one\n\n1109 two\n\n1110 three, phone\n';
    final d = await _repo(prior, pulled);
    try {
      File('${d.path}/Journal/Nov 14th.md').writeAsStringSync(late);
      final repo = git.Repository.open(d.path);
      expect(commitDirtyTree(repo, '202611141243', 'iPhone'), isTrue);
      final note = File('${d.path}/Journal/Nov 14th.md').readAsStringSync();
      expect(note, '1107 one, computer\n\n1109 two\n\n1110 three, phone\n');
      expect(await scanForConflicts(d.path), isEmpty);
      repo.free();
    } finally {
      await d.delete(recursive: true);
    }
  });

  test('typed on top of the pulled text: one ordinary commit', () async {
    const prior = '1107 one\n';
    const pulled = '1107 one\n\n1109 computer\n';
    final d = await _repo(prior, pulled);
    try {
      File('${d.path}/Journal/Nov 14th.md').writeAsStringSync('$pulled\n1130 phone\n');
      final repo = git.Repository.open(d.path);
      expect(commitDirtyTree(repo, '202611141243', 'iPhone'), isTrue);
      expect(_git(d.path, ['log', '-1', '--format=%P']).split(' ').length, 1);
      expect(File('${d.path}/Journal/Nov 14th.md').readAsStringSync(), '$pulled\n1130 phone\n');
      repo.free();
    } finally {
      await d.delete(recursive: true);
    }
  });
}
