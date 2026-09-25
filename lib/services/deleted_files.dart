// services/deleted_files.dart
//
// 2026-09-25: Ken - "how will a user work with files on the desktop and
// phone ... without wiping data?" A deletion on one device is synced to
// the other (that's what sync means), but every version stays in the
// folder's history. This lists files that were deleted, on either device,
// and puts one back - no git knowledge needed.
//
// Reads the phone's own copy of the history (the folder's .git), so it
// works offline. A restored file is a normal new file: the next Push
// sends it to the desktop.
import 'dart:io';
import 'package:git2dart/git2dart.dart' as git;
import 'vault_backup.dart' show kLocalSyncFolderName;

class DeletedFile {
  final String path; // relative to the synced folder
  final DateTime deletedAt;
  final String blobOid; // the last version before it was deleted
  final String deletedBy; // commit author, e.g. "iPhone" / "desktop ..."
  const DeletedFile(this.path, this.deletedAt, this.blobOid, this.deletedBy);
}

/// Files deleted in the last [maxCommits] commits that are still missing
/// now, newest deletion first. LocalSync's own folder is left out.
List<DeletedFile> listDeletedFiles(String folderPath, {int maxCommits = 1000}) {
  final repo = git.Repository.open(folderPath);
  try {
    final walker = git.RevWalk(repo);
    walker.sorting({git.GitSort.time});
    walker.pushHead();
    final found = <String, DeletedFile>{};
    for (final commit in walker.walk(limit: maxCommits)) {
      final parents = commit.parents;
      if (parents.isEmpty) continue;
      final parent = git.Commit.lookup(repo: repo, oid: parents.first);
      final diff = git.Diff.treeToTree(
          repo: repo, oldTree: parent.tree, newTree: commit.tree);
      for (final d in diff.deltas) {
        if (d.status != git.GitDelta.deleted) continue;
        final path = d.oldFile.path;
        if (path.startsWith('$kLocalSyncFolderName/') ||
            path.split('/').any((s) => s.startsWith('.'))) {
          continue;
        }
        if (found.containsKey(path)) continue; // newest deletion wins
        found[path] = DeletedFile(
          path,
          DateTime.fromMillisecondsSinceEpoch(commit.time * 1000),
          d.oldFile.oid.sha,
          commit.author.name,
        );
      }
    }
    // Only what's still missing - a file re-added later isn't "deleted".
    return found.values
        .where((f) => !File('$folderPath/${f.path}').existsSync())
        .toList()
      ..sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
  } finally {
    repo.free();
  }
}

/// Writes the last version of [file] back into the folder. Never
/// overwrites: if something now sits at that path, the restored copy gets
/// " (restored)" before its extension. Returns the path written.
String restoreDeletedFile(String folderPath, DeletedFile file) {
  final repo = git.Repository.open(folderPath);
  try {
    final blob = git.Blob.lookup(repo: repo, oid: git.Oid.fromSHA(repo, file.blobOid));
    var target = '$folderPath/${file.path}';
    if (File(target).existsSync()) {
      final dot = target.lastIndexOf('.');
      final slash = target.lastIndexOf('/');
      target = dot > slash
          ? '${target.substring(0, dot)} (restored)${target.substring(dot)}'
          : '$target (restored)';
    }
    final out = File(target);
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(blob.contentBytes);
    return target.substring(folderPath.length + 1);
  } finally {
    repo.free();
  }
}
