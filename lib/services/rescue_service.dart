// services/rescue_service.dart
//
// 2026-09-29: user - Rescue Package: "one payment, one button, one tap ...
// the user in panic knows they just need to hit one big red button and it
// all auto happens." Every synced folder, in one go, using only what
// LocalSync already does one step at a time:
//   1. lost notes: every note removed in the last 30 days is put back from
//      the folder's own history (restoreDeletedFile - never overwrites,
//      a clash gets " (restored)")
//   2. conflicts: every conflict kept and cleaned up (Keep both & clean up)
//   3. SYNC CONFLICT boxes: merged, keeping both sides
//   4. push, so the desktop gets it all too
// Nothing is ever deleted: "never lose data" beats "never duplicate" - a
// note deleted on purpose in the last 30 days comes back and can simply be
// deleted again. Before changing a note, conflict repair already saves the
// old text to LocalSync/Conflict Backups.
import '../models/repository.dart';
import 'conflict_scanner.dart';
import 'deleted_files.dart';
import 'demo_conflict.dart';
import 'repository_provider.dart';

const kRescueLookBack = Duration(days: 30);

// 2026-09-29: OFF - first real use put back 271 deliberately deleted
// LocalSync backup copies (Projects/LocalSync/Conflict Backups - the
// LocalSync folder wasn't at the vault root) and flooded Obsidian with
// duplicate reminders; undone with git revert 4355fadc. Menu item, price
// card and trouble alert all stay hidden until Rescue is rebuilt: never
// inside any LocalSync folder, only the one big disappearance, then sync.
const kRescueEnabled = false;

class RescueResult {
  int notesBack = 0;
  int conflictsFixed = 0;
  final List<String> problems = [];
  bool get anythingDone => notesBack > 0 || conflictsFixed > 0;
}

Future<RescueResult> runRescue(RepositoryProvider provider,
    {void Function(String step)? onStep}) async {
  final result = RescueResult();
  final cutoff = DateTime.now().subtract(kRescueLookBack);
  final repos = List<Repository>.of(provider.repos)
      .where((r) => !DemoConflict.isDemo(r));
  for (final repo in repos) {
    onStep?.call('Checking ${repo.name}');
    try {
      final changed = await provider.withRepoFolder(repo, (path) async {
        final r = await rescueFolder(path, cutoff);
        result.notesBack += r.notesBack;
        result.conflictsFixed += r.conflictsFixed;
        return r.notesBack + r.conflictsFixed;
      });
      if (changed == null) {
        result.problems.add('${repo.name}: folder could not be opened');
        continue;
      }
      if (changed > 0 && repo.id != null) {
        onStep?.call('Sending ${repo.name} to your desktop');
        await provider.pushRepository(repo.id!,
            commitMessage: 'Rescue: lost notes back, conflicts cleaned up');
      }
    } catch (e) {
      result.problems.add('${repo.name}: $e');
    }
  }
  return result;
}

/// One synced folder: notes removed since [cutoff] put back, every conflict
/// and SYNC CONFLICT box merged keeping both. Nothing is ever deleted.
Future<({int notesBack, int conflictsFixed})> rescueFolder(
    String path, DateTime cutoff) async {
  var notes = 0, conflicts = 0;
  for (final f in listDeletedFiles(path)) {
    if (f.deletedAt.isBefore(cutoff)) continue;
    restoreDeletedFile(path, f);
    notes++;
  }
  for (final c in await scanForConflicts(path)) {
    await mergeConflictKeepingBoth(path, c, cleanUp: true);
    conflicts++;
  }
  for (final r in await scanForReferenceCallouts(path)) {
    await mergeReferenceKeepingBoth(path, r);
    conflicts++;
  }
  return (notesBack: notes, conflictsFixed: conflicts);
}
