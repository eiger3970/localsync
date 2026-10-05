// test/free_folder_conflict_test.dart
//
// 2026-10-05: user - "for free sync, if I edit a text file on phone and
// desktop, then sync, does it break?" It did: the everyday pull only
// repaired .md conflicts, so a .txt changed on both sides stayed
// conflicted and finishMergeCommit threw mid-merge. This builds the exact
// case from scratch (no fixture - git2dart's merge_repo fixture isn't in
// the published package): a "desktop" repo, a "phone" clone, both edit
// the same .txt, the phone fetches and merges, then the same repair the
// pull now runs. Runs on GitHub's x86 runner (Tests workflow) - the
// git2dart binaries are x86-only, so not on the Pi.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:git2dart/git2dart.dart' as git;
import 'package:localsync/services/localsync_folder.dart';
import 'package:localsync/services/sync_service.dart';

void _firstCommit(git.Repository repo) {
  final idx = repo.index;
  idx.addAll(['.']);
  idx.write();
  final tree = git.Tree.lookup(repo: repo, oid: idx.writeTree());
  final sig = git.Signature.create(name: 'test', email: 'test@example.com');
  git.Commit.create(repo: repo, updateRef: 'HEAD', author: sig,
      committer: sig, message: 'base', tree: tree, parents: []);
}

void main() {
  late Directory tmp;

  setUp(() {
    git.Libgit2.ownerValidation = false;
    tmp = Directory.systemTemp.createTempSync('free_folder_conflict_');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('a .txt edited on phone and desktop syncs: phone kept, desktop in Backups, no failure', () {
    final desktopPath = '${tmp.path}/desktop', phonePath = '${tmp.path}/phone';
    final desktop = git.Repository.init(path: desktopPath);
    File('$desktopPath/note.txt').writeAsStringSync('base text\n');
    _firstCommit(desktop);

    final phone = git.Repository.clone(url: desktopPath, localPath: phonePath);

    File('$desktopPath/note.txt').writeAsStringSync('desktop edit\n');
    expect(commitDirtyTree(desktop, 'desktop change', 'desktop'), isTrue);
    File('$phonePath/note.txt').writeAsStringSync('phone edit\n');
    expect(commitDirtyTree(phone, 'phone change', 'phone'), isTrue);

    // What the everyday pull does: fetch, merge the desktop's branch.
    git.Remote.lookup(repo: phone, name: 'origin').fetch();
    final branch = phone.head.name.replaceFirst('refs/heads/', '');
    final remoteOid = git.Reference.lookup(
        repo: phone, name: 'refs/remotes/origin/$branch').target;
    git.Merge.commit(repo: phone,
        commit: git.AnnotatedCommit.lookup(repo: phone, oid: remoteOid));
    expect(phone.index.hasConflicts, isTrue, reason: 'the case user asked about');

    // The repair the pull now runs for non-.md files.
    repairAllConflictsOnDisk(phonePath, otherLabel: 'desktop');
    final kept = repairBinaryConflictsOnDisk(phone, phonePath, otherLabel: 'desktop');
    expect(kept, 1);
    expect(phone.index.hasConflicts, isFalse);

    // Used to throw here - now the merge finishes.
    finishMergeCommit(phone, 'phone', message: 'Merge desktop and phone');
    phone.stateCleanup();

    expect(File('$phonePath/note.txt').readAsStringSync(), 'phone edit\n');
    final backups = Directory(conflictBackupsDir(phonePath))
        .listSync(recursive: true).whereType<File>()
        .map((f) => f.readAsStringSync()).toList();
    expect(backups, contains('desktop edit\n'), reason: 'nothing lost');
  });
}
