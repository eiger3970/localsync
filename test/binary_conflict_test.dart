// 2026-08-27: real gap found - sync_service.dart's repairAllConflictsOnDisk
// only ever handled .md files. Any other conflicted file (an image/PDF in
// an existing Obsidian vault, or any file at all in a Tier 0 generic-sync
// repo) fell straight through to finishMergeCommit with whatever libgit2's
// default merge left on disk - no backup, no detection, no user
// visibility. This exercises the fix (repairBinaryConflictsOnDisk) against
// a real git2dart merge conflict, not a simulated one - reuses git2dart's
// own bundled test fixture (test/assets/merge_repo, has a real
// 'conflict-branch' that conflicts on a non-.md file called
// 'conflict_file') rather than hand-building a divergent-history repo from
// scratch, since git2dart's own test suite already proves that fixture
// produces a genuine index conflict.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:git2dart/git2dart.dart' as git;
import 'package:localsync/services/sync_service.dart';
import 'package:localsync/services/vault_backup.dart';

/// Resolves where git2dart's own package source lives on disk for *this*
/// project's actual resolved version - not a hardcoded version-specific
/// path, so this keeps working if git2dart is ever bumped.
Directory _git2dartFixtureDir() {
  final config = jsonDecode(
      File('.dart_tool/package_config.json').readAsStringSync())
      as Map<String, dynamic>;
  final packages = config['packages'] as List<dynamic>;
  final git2dart = packages.firstWhere((p) => p['name'] == 'git2dart')
      as Map<String, dynamic>;
  final rootUri = (git2dart['rootUri'] as String).replaceFirst('file://', '');
  return Directory('$rootUri/test/assets/merge_repo');
}

/// Mirrors git2dart's own test/helpers/util.dart copyRepo - not importable
/// directly (it's a private test helper, not part of the public package),
/// so reimplemented here. The fixture stores its .git as a plain folder
/// named '.gitdir' (so it isn't itself treated as a real git repo/
/// submodule sitting inside git2dart's own checkout).
void _copyFixture(Directory from, Directory to) {
  for (final entity in from.listSync()) {
    final base = entity.path.split('/').last;
    if (entity is Directory) {
      final destName = base == '.gitdir' ? '.git' : base;
      final dest = Directory('${to.path}/$destName')..createSync();
      _copyFixture(entity, dest);
    } else if (entity is File) {
      final destName = base == 'gitignore'
          ? '.gitignore'
          : base == 'gitattributes'
              ? '.gitattributes'
              : base;
      File('${to.path}/$destName')
          .writeAsBytesSync(entity.readAsBytesSync());
    }
  }
}

void main() {
  late Directory tmpDir;
  late git.Repository repo;

  setUp(() {
    git.Libgit2.ownerValidation = false;
    tmpDir = Directory.systemTemp.createTempSync('binary_conflict_test_');
    _copyFixture(_git2dartFixtureDir(), tmpDir);
    repo = git.Repository.open(tmpDir.path);
    repo.reset(oid: repo.head.target, resetType: git.GitReset.hard);
  });

  tearDown(() {
    repo.free();
    tmpDir.deleteSync(recursive: true);
  });

  group('repairBinaryConflictsOnDisk', () {
    test('backs up both sides, keeps ours, and clears the index conflict',
        () {
      final conflictBranch =
          git.Branch.lookup(repo: repo, name: 'conflict-branch');
      final oursContentBefore =
          File('${tmpDir.path}/conflict_file').readAsBytesSync();

      git.Merge.commit(
        repo: repo,
        commit: git.AnnotatedCommit.lookup(
            repo: repo, oid: conflictBranch.target),
      );
      expect(repo.index.hasConflicts, isTrue);
      expect(repo.index.conflicts.containsKey('conflict_file'), isTrue);

      final theirsBlob = git.Blob.lookup(
          repo: repo, oid: repo.index.conflicts['conflict_file']!.their!.oid);
      final theirsContent = theirsBlob.contentBytes;

      final resolved =
          repairBinaryConflictsOnDisk(repo, tmpDir.path, otherLabel: 'desktop');

      expect(resolved, 1);
      expect(repo.index.hasConflicts, isFalse);

      // Working file now holds exactly "ours" - deterministic, not
      // whatever libgit2's own default merge left behind.
      final workingContent =
          File('${tmpDir.path}/conflict_file').readAsBytesSync();
      expect(workingContent, oursContentBefore);

      // Both sides are recoverable from Conflict Backups - nothing
      // silently lost, same convention as the markdown conflict path.
      final backupDir =
          Directory('${tmpDir.path}/$kLocalSyncFolderName/Conflict Backups');
      final backups = backupDir.listSync().map((e) => e.path.split('/').last).toList();
      expect(backups.any((n) => n.startsWith('conflict_file - yours - ')),
          isTrue);
      expect(backups.any((n) => n.startsWith('conflict_file - desktop - ')),
          isTrue);
      final theirsBackup = backupDir
          .listSync()
          .firstWhere((e) => e.path.contains(' - desktop - ')) as File;
      expect(theirsBackup.readAsBytesSync(), theirsContent);
    });

    test('never touches .md conflicts - repairAllConflictsOnDisk owns those',
        () {
      File('${tmpDir.path}/note.md').writeAsStringSync(
        '> [!warning]+ SYNC CONFLICT — yours (review and delete one)\n'
        '> mine\n'
        '<<<<<<< also has a literal marker string, should never match this scanner\n',
      );
      final resolved = repairBinaryConflictsOnDisk(repo, tmpDir.path);
      expect(resolved, 0);
      // Untouched - still exactly what was written above.
      expect(File('${tmpDir.path}/note.md').readAsStringSync(),
          contains('mine'));
    });
  });
}
