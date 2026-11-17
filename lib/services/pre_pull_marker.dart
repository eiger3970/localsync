import 'dart:convert';
import 'dart:io';

/// 2026-11-14: written by every pull (sync_service.dart notePrePull): the phone's commit from before the pull. A note
/// saved within 15 min that drops every line the pull added is treated as Obsidian writing its OLD copy and is merged
/// by git (mergeStaleSavesWithGit).
const kPrePullFile = 'localsync_pre_pull_head';

/// 2026-11-14 owner, real test: "After conflict and push the desktop should show the phone's entry". Picking
/// "phone again" in Conflicts removed the computer's line, which looked exactly like an old Obsidian copy, so the pick
/// was merged again and the computer's line came back. A choice made in Conflicts is deliberate: it clears the marker.
void clearPrePullMarker(String vaultPath) {
  try {
    final f = File('$vaultPath/.git/$kPrePullFile');
    if (f.existsSync()) f.deleteSync();
  } catch (_) {}
}

// 2026-11-17 owner, real Test E2: KEEP BOTH & CLEAN UP wrote both lines, but Obsidian (open in the background with
// the note) saved its OLD copy back over the fix before the next sync, so "E3 PHONE" left the note. Every fix made in
// Conflicts is noted here (the note's text before and after). Before each commit, a note that is back to EXACTLY
// its text from before the fix, within 15 minutes, is Obsidian's old copy: the fix is written again. Anything typed
// since (text not exactly the old copy) is left alone. UNDO forgets the note first, so UNDO is never re-fixed.
const kResolvedFile = 'localsync_resolved_notes.json';
const _kResolvedWindow = Duration(minutes: 15);

File _resolvedFile(String vaultPath) => File('$vaultPath/.git/$kResolvedFile');

List<Map<String, dynamic>> _readResolved(String vaultPath) {
  try {
    final f = _resolvedFile(vaultPath);
    if (!f.existsSync()) return [];
    return (jsonDecode(f.readAsStringSync()) as List).cast<Map<String, dynamic>>();
  } catch (_) {
    return [];
  }
}

void _writeResolved(String vaultPath, List<Map<String, dynamic>> list) {
  try {
    final f = _resolvedFile(vaultPath);
    if (list.isEmpty) {
      if (f.existsSync()) f.deleteSync();
      return;
    }
    f.writeAsStringSync(jsonEncode(list));
  } catch (_) {}
}

void noteResolution(String vaultPath, String relPath, String before, String after) {
  if (before == after) return;
  final list = _readResolved(vaultPath)..removeWhere((r) => r['path'] == relPath);
  list.add({'path': relPath, 'before': before, 'after': after, 'at': DateTime.now().millisecondsSinceEpoch});
  _writeResolved(vaultPath, list);
}

void forgetResolution(String vaultPath, String relPath) {
  final list = _readResolved(vaultPath);
  final n = list.length;
  list.removeWhere((r) => r['path'] == relPath);
  if (list.length != n) _writeResolved(vaultPath, list);
}

/// Writes a fix again where Obsidian saved the note's old copy over it. Returns the notes fixed again.
List<String> restoreStaleResolutionSaves(String vaultPath) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final list = _readResolved(vaultPath)
    ..removeWhere((r) => now - (r['at'] as int) > _kResolvedWindow.inMilliseconds);
  final restored = <String>[];
  for (final r in list) {
    try {
      final f = File('$vaultPath/${r['path']}');
      if (!f.existsSync()) continue;
      if (f.readAsStringSync() == r['before']) {
        f.writeAsStringSync(r['after'] as String);
        restored.add(r['path'] as String);
      }
    } catch (_) {}
  }
  _writeResolved(vaultPath, list);
  return restored;
}
