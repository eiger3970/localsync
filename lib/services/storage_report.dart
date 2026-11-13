// services/storage_report.dart
//
// 2026-11-13 owner: "Obsidian is 2.81 GB, help me find large files, as text can't take up that much room". The
// notes themselves are ~20 MB; the rest sits in hidden folders the Files app never shows. Two parts:
//
//  1. storageReport(): folder sizes inside the vault (top level, plus .git split into loose/packed and
//     .localsync_backups split per backup), for Send details. Folder names only, never note names or text.
//  2. compactGitStore(): the phone's git library (libgit2) never runs "git gc", so every sync leaves each changed
//     file as its own loose object, forever. This packs every object into one compressed pack (same content, nothing
//     dropped: unreachable objects are packed too), checks the new pack holds every object, and only then removes the
//     loose copies and the old packs. If anything fails before that check passes, nothing old is touched.
import 'dart:io';
import 'dart:isolate';
import 'package:git2dart/git2dart.dart';

int _dirBytes(Directory d) {
  var total = 0;
  try {
    for (final e in d.listSync(recursive: true, followLinks: false)) {
      if (e is File) {
        try {
          total += e.lengthSync();
        } catch (_) {}
      }
    }
  } catch (_) {}
  return total;
}

String formatBytes(int b) {
  if (b >= 1 << 30) return '${(b / (1 << 30)).toStringAsFixed(2)} GB';
  if (b >= 1 << 20) return '${(b / (1 << 20)).toStringAsFixed(0)} MB';
  return '${(b / 1024).toStringAsFixed(0)} KB';
}

final _hex2 = RegExp(r'^[0-9a-f]{2}$');
const kBackupsDir = '.localsync_backups';

/// Loose object count and bytes in [gitDir]/objects.
(int, int) looseObjects(String gitDir) {
  var n = 0, bytes = 0;
  final objs = Directory('$gitDir/objects');
  if (!objs.existsSync()) return (0, 0);
  for (final d in objs.listSync(followLinks: false)) {
    if (d is! Directory || !_hex2.hasMatch(d.uri.pathSegments.where((s) => s.isNotEmpty).last)) continue;
    for (final f in d.listSync(followLinks: false)) {
      if (f is File) {
        n++;
        try {
          bytes += f.lengthSync();
        } catch (_) {}
      }
    }
  }
  return (n, bytes);
}

String _storageReportSync(String vaultPath) {
  final root = Directory(vaultPath);
  if (!root.existsSync()) return 'Storage: folder not found';
  // One walk over every file (a big vault has hundreds of thousands): top-level totals, .git split, backups per
  // folder, and each folder's own files.
  final top = <String, int>{};
  final backups = <String, int>{};
  final own = <String, int>{};
  var looseN = 0, looseB = 0, packB = 0, files = 0;
  final cut = vaultPath.length + 1;
  try {
    for (final e in root.listSync(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      int len;
      try {
        len = e.lengthSync();
      } catch (_) {
        continue;
      }
      files++;
      final rel = e.path.substring(cut);
      final slash = rel.indexOf('/');
      final first = slash == -1 ? '' : rel.substring(0, slash);
      final key = first.startsWith('.') ? first : 'notes and attachments (all visible folders)';
      top[key] = (top[key] ?? 0) + len;
      if (first == '.git') {
        if (rel.startsWith('.git/objects/pack/')) {
          packB += len;
        } else if (rel.length > 15 && _hex2.hasMatch(rel.substring(13, 15)) && rel[15] == '/' &&
            rel.startsWith('.git/objects/')) {
          looseN++;
          looseB += len;
        }
        if (rel.startsWith('.git/objects/')) continue;
      }
      if (first == kBackupsDir) {
        final rest = rel.substring(slash + 1);
        final s2 = rest.indexOf('/');
        if (s2 != -1) {
          final b = rest.substring(0, s2);
          backups[b] = (backups[b] ?? 0) + len;
        }
      }
      final dirRel = e.parent.path.length > vaultPath.length ? e.parent.path.substring(cut) : '(top)';
      own[dirRel] = (own[dirRel] ?? 0) + len;
    }
  } catch (_) {}
  final rows = top.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  final total = rows.fold<int>(0, (s, r) => s + r.value);
  final b = StringBuffer('Storage: ${formatBytes(total)} in total, $files files\n');
  for (final r in rows) {
    b.writeln('- ${r.key}: ${formatBytes(r.value)}');
    if (r.key == '.git') {
      b.writeln('  - sync history, unpacked: ${formatBytes(looseB)} ($looseN items)');
      b.writeln('  - sync history, packed: ${formatBytes(packB)}');
    }
    if (r.key == kBackupsDir) {
      final bl = backups.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      for (final x in bl) {
        b.writeln('  - ${x.key}: ${formatBytes(x.value)}');
      }
    }
  }
  final big = own.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  b.writeln('Biggest folders:');
  for (final e in big.take(10)) {
    b.writeln('- ${e.key}: ${formatBytes(e.value)}');
  }
  return b.toString().trimRight();
}

/// Folder sizes for Send details, worked out off the main thread (a big vault takes seconds).
Future<String> storageReport(String vaultPath) =>
    Isolate.run(() => _storageReportSync(vaultPath));

class CompactResult {
  final int beforeBytes;
  final int afterBytes;
  final int objects;
  const CompactResult(this.beforeBytes, this.afterBytes, this.objects);
}

/// Packs loose objects when there are at least [minLoose]. Returns null when nothing needed doing.
/// Throws on failure; old objects are only removed after the new pack is checked to hold every one of them.
CompactResult? compactGitStoreSync(String vaultPath, {int minLoose = 300}) {
  final gitDir = '$vaultPath/.git';
  final (loose, _) = looseObjects(gitDir);
  if (loose < minLoose) return null;
  final before = _dirBytes(Directory('$gitDir/objects'));
  final tmp = Directory('$gitDir/localsync_pack_tmp');
  if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  Directory('${tmp.path}/pack').createSync(recursive: true);
  try {
    final repo = Repository.open(vaultPath);
    // An object can sit both loose and in a pack: count each once.
    final seen = <String>{};
    final oids = [for (final o in repo.odb.objects) if (seen.add(o.sha)) o];
    final written = repo.pack(
        path: '${tmp.path}/pack',
        threads: 2,
        packDelegate: (pb) {
          for (final o in oids) {
            pb.add(o);
          }
        });
    repo.free();
    if (written < oids.length) {
      throw StateError('pack wrote $written of ${oids.length} objects');
    }
    // The new pack alone must hold every object, or nothing old is removed.
    final check = Odb.create()..addDiskAlternate(tmp.path);
    for (final o in oids) {
      if (!check.contains(o)) throw StateError('new pack is missing an object');
    }
    check.free();
    final newFiles = Directory('${tmp.path}/pack').listSync().whereType<File>().toList();
    final newNames = {for (final f in newFiles) f.uri.pathSegments.last};
    final packDir = Directory('$gitDir/objects/pack')..createSync(recursive: true);
    for (final f in newFiles) {
      f.renameSync('${packDir.path}/${f.uri.pathSegments.last}');
    }
    // Every object is now in the new pack: the loose copies and the old packs are duplicates.
    for (final f in packDir.listSync().whereType<File>()) {
      final n = f.uri.pathSegments.last;
      if (!newNames.contains(n) && n.startsWith('pack-')) f.deleteSync();
    }
    for (final d in Directory('$gitDir/objects').listSync(followLinks: false)) {
      if (d is Directory && _hex2.hasMatch(d.uri.pathSegments.where((s) => s.isNotEmpty).last)) {
        d.deleteSync(recursive: true);
      }
    }
    final after = _dirBytes(Directory('$gitDir/objects'));
    return CompactResult(before, after, oids.length);
  } finally {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  }
}

Future<CompactResult?> compactGitStore(String vaultPath, {int minLoose = 300}) =>
    Isolate.run(() => compactGitStoreSync(vaultPath, minLoose: minLoose));
