// services/rescue_service.dart
//
// 2026-09-29: Ken - Rescue Package: "one payment, one button, one tap ...
// the user in panic knows they just need to hit one big red button and it
// all auto happens." Every synced folder, in one go:
//   1. notes missing right now that never synced as deleted, and the last
//      big disappearance (20+ notes in one sync within 30 days) - put back
//      from the folder's own history (never overwrites, a clash gets
//      " (restored)"); never anything inside a LocalSync folder, any depth
//   2. conflicts: every conflict kept and cleaned up (Keep both & clean up)
//   3. SYNC CONFLICT boxes: merged, keeping both sides
//   4. push, then the desktop sync runs straight away
// Nothing is ever deleted. Before changing a note, conflict repair saves
// the old text to LocalSync/Conflict Backups.
import 'dart:io';
import 'dart:isolate';
import '../models/repository.dart';
import 'conflict_scanner.dart';
import 'deleted_files.dart';
import 'demo_conflict.dart';
import 'repository_provider.dart';

const kRescueLookBack = Duration(days: 30);

// 2026-09-29: was OFF after the first real use put back 271 deliberately deleted
// LocalSync backup copies (Projects/LocalSync/Conflict Backups - the
// LocalSync folder wasn't at the vault root) and flooded Obsidian with
// duplicate reminders; undone with git revert 4355fadc. Menu item, price
// card and trouble alert were hidden until Rescue was rebuilt the same day:
// never inside any LocalSync folder (any depth), only notes missing right
// now + the last big disappearance, heavy work off the UI thread, then the
// desktop sync runs straight away.
const kRescueEnabled = true;

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
        // 2026-09-29: Ken - "I tapped the button and nothing happened ...
        // after 30 seconds the word RESCUE changed to DONE." The history
        // walk ran on the UI thread and froze the screen; off it now.
        final r = await Isolate.run(() => rescueFolder(path, cutoff));
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
        // "A sync needs to run after a fix" - the desktop gets it now,
        // not at its next 5-minute run.
        onStep?.call('Updating your desktop');
        await provider.triggerDesktopSyncNow(repo.id!);
      }
    } catch (e) {
      result.problems.add('${repo.name}: $e');
    }
  }
  return result;
}

/// One synced folder: notes missing right now (never synced as deleted)
/// and the last big disappearance (20+ at once since [cutoff]) put back,
/// every conflict and SYNC CONFLICT box merged keeping both. Never inside
/// a LocalSync folder, nothing is ever deleted.
Future<({int notesBack, int conflictsFixed})> rescueFolder(
    String path, DateTime cutoff) async {
  var notes = 0, conflicts = 0;
  final seen = <String>{};
  for (final f in [
    ...listMissingNow(path),
    ...listLastMassDeletion(path, since: cutoff),
  ]) {
    if (!seen.add(f.path) || File('$path/${f.path}').existsSync()) continue;
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
