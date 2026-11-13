import 'dart:isolate';
import 'dart:io';
// widgets/auto_sync_on_resume.dart
//
// 2026-09-06: real feedback, live - "how does a user avoid this issue?"
// Sync only ever ran on an explicit swipe/tap before this, so a real
// edit could sit unpushed for the entire time between making it and
// remembering to open LocalSync and swipe PUSH - exactly the window a
// later reset (or, per the same day's other real incident, Obsidian's
// own file cache) can silently discard content in. This shrinks that
// window automatically: every time the app becomes the foreground app
// (cold launch or resuming from background), it pushes then pulls on
// its own, no tap required.
//
// Wraps HomeScreen from outside rather than living inside it -
// HomeScreen's own build method is already large, and this concern
// (app-lifecycle-driven sync) has nothing to do with anything else
// that screen renders. Works the same regardless of which of
// HomeScreen's two entry points (main.dart's initial route,
// linking_screen.dart's post-setup navigation) reached it, since both
// wrap their HomeScreen the same way.
//
// Deliberately silent - no SnackBar, no dialog of its own. This is a
// quiet background top-up, not a replacement for the real swipe
// gesture: anything that needs a human decision (a genuine conflict,
// a large-deletion confirmation) is left exactly as it already sits
// today, surfaced the same way it always has been - by the user's own
// next manual PUSH/PULL, or the Conflicts screen. Real conflict/backup
// handling and messaging are unchanged; this only changes how OFTEN a
// push/pull gets a chance to run at all.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/repository.dart';
import '../services/localsync_cleanup.dart';
import '../services/repository_provider.dart';
import '../theme.dart';
import '../services/widget_action.dart';
import '../screens/backups_screen.dart';
import '../services/vault_backup.dart' show kFullBackupsFolder;
import 'package:url_launcher/url_launcher.dart';

class AutoSyncOnResume extends StatefulWidget {
  final Widget child;
  const AutoSyncOnResume({super.key, required this.child});

  @override
  State<AutoSyncOnResume> createState() => _AutoSyncOnResumeState();
}

class _AutoSyncOnResumeState extends State<AutoSyncOnResume>
    with WidgetsBindingObserver {
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Cold launch counts as "became the foreground app" too - the
    // lifecycle callback alone only fires on a RESUME from background,
    // never on the very first launch.
    //
    // 2026-09-22: real crash/glitch found live - a widget tap is a cold
    // launch, and main.dart's widget-action MethodChannel check is a
    // real async round trip that doesn't necessarily resolve by the
    // first frame. Firing _autoSync() straight off addPostFrameCallback
    // used to run this before that check could possibly have set
    // pendingQuickAction, so the `if (provider.pendingQuickAction !=
    // null) return` guard below saw "nothing pending yet" and launched
    // its own redundant silent push+pull, then the widget's real one ran
    // moments later once the channel resolved - a real double-sync (the
    // double-gif symptom on push, likely a contributor to the pull
    // crash too). Awaiting pendingActionCheckDone here only delays the
    // COLD LAUNCH path - it resolves once, at startup, so it's already
    // complete on every later resume-from-background call below.
    WidgetsBinding.instance.addPostFrameCallback((_) => _gatedAutoSync());
    // 2026-11-13 owner: the backup check also follows the person's own PULL/PUSH, not only the hidden automatic
    // sync. Runs 2 s after a sync finishes, once nothing else is syncing.
    _provider = context.read<RepositoryProvider>()..addListener(_onProvider);
    _seenSyncs = _provider!.syncsDone;
  }

  RepositoryProvider? _provider;
  int _seenSyncs = 0;
  bool _checking = false;
  void _onProvider() {
    final p = _provider!;
    if (p.syncsDone == _seenSyncs) return;
    _seenSyncs = p.syncsDone;
    if (_syncing || _checking) return;
    _checking = true;
    Future.delayed(const Duration(seconds: 2), () async {
      try {
        final repo = p.selectedRepo;
        if (mounted && !_syncing && !p.syncBusy && repo?.id != null) await _offerToFreeSpace(p, repo!);
      } catch (_) {
      } finally {
        _checking = false;
      }
    });
  }

  @override
  void dispose() {
    _provider?.removeListener(_onProvider);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 2026-09-22: real crash, live, confirmed via a fresh on-device .ips
    // log AGAIN, on a build that already had every other fix this
    // exact crash class has gotten today (the widget cold-launch race
    // above, RepositoryProvider._init()'s own gating, the native
    // double-delivery dedup in SceneDelegate.swift) - same
    // concurrent-git_remote_connect BoringSSL abort every time. This
    // callback was the real remaining gap: it called _autoSync()
    // directly, with NONE of the pendingActionCheckDone gating the
    // initState path above got - a widget/URL-triggered cold launch can
    // plausibly deliver an explicit inactive->resumed transition here
    // (a different OS-level activation path than a plain icon tap),
    // racing the widget's real action through a door that was never
    // actually closed. Routed through the same gate now.
    if (state == AppLifecycleState.resumed) _resumed();
  }

  // 2026-09-24: real feedback, live - "Widgets push and pull causes a
  // home screen black out, rather than gif and graphics." A widget tap
  // on a warm app arrives as a plain resume, and nothing read the
  // pending action here - the silent auto-sync ran instead. Read it
  // first (services/widget_action.dart, consume-on-read, so a cold
  // launch's own startup check and this can never both run it). If
  // there is one, hand it to HomeScreen's pendingQuickAction watcher,
  // which runs it through _runAndShow (gif, result SnackBar, chime);
  // _autoSync already steps aside while a quick action is pending.
  Future<void> _resumed() async {
    final action = await takePendingWidgetAction();
    if (!mounted) return;
    if (action != null) {
      context.read<RepositoryProvider>().setPendingQuickAction(action);
      return;
    }
    _gatedAutoSync();
  }

  Future<void> _gatedAutoSync() async {
    if (!mounted) return;
    await context.read<RepositoryProvider>().pendingActionCheckDone;
    if (!mounted) return;
    _autoSync();
  }

  Future<void> _autoSync() async {
    // 2026-08-21's own _run()/_runLocked() already serializes concurrent
    // push/pulls per repo id (awaits any prior in-flight one first) -
    // this flag is just to skip scheduling a redundant second attempt
    // from rapid resume/foreground churn, not real locking.
    if (_syncing || !mounted) return;
    final provider = context.read<RepositoryProvider>();
    // 2026-09-16: real feedback, live - "long tapped app icon -> tapped
    // push -> app opened to home screen pulling... should say pushing
    // right?" Root cause: this runs its own silent push-then-pull on
    // EVERY cold launch, completely independent of Quick Actions - a
    // Quick Action tap and this auto-sync both fire on the same cold
    // launch, serialized behind each other via _run's own per-repo
    // lock, so whichever one the user actually tapped gets buried
    // behind (and visually indistinguishable from) this silent one.
    // When a Quick Action is already about to run an explicit,
    // visible sync, this auto one is redundant - skip it and let the
    // explicit one be the only thing that runs, not two racing.
    if (provider.pendingQuickAction != null ||
        provider.quickActionJustHandled) {
      return;
    }
    final repo = provider.selectedRepo;
    if (repo?.id == null) return;
    // 2026-09-27: real feedback, live - "I unlocked the phone to check
    // and localsync looked finished, but then started auto syncing
    // again, taking forever." Unlocking is a resume; a sync that just
    // finished gets nothing new from an immediate second one (the
    // desktop only moves every 5 min). A manual swipe still always runs.
    final last = repo!.lastSync;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(minutes: 2)) {
      return;
    }
    _syncing = true;
    try {
      // Push first - carries forward any real local edit before
      // anything else gets a chance to touch it - then pull, same
      // order a manual "catch up both ways" session would use.
      await provider.pushRepository(repo.id!, background: true);
      if (!mounted) return;
      await provider.pullRepository(repo.id!, background: true);
      if (mounted) await _offerToFreeSpace(provider, repo);
    } catch (_) {
      // Best-effort only - a real failure here is left for the user's
      // own next manual sync to surface properly, not narrated here.
    } finally {
      _syncing = false;
    }
  }

  // 2026-11-13 owner: "when the user is seeing phone storage full errors, the user doesn't know where to go ... deletes
  // [the app] ... negative reviews". The old one-copy question (asked once, a week after linking) let 36 copies, 1.78 GB,
  // pile up silently after a single KEEP. Now LocalSync watches the size: once its backups pass 500 MB it says how much,
  // where iPhone shows it (under Obsidian, not LocalSync), and offers DELETE ALL. Asked again only after another 500 MB.
  // The answer is kept next to the backups (.size_asked), so a reinstall does not ask again. Nothing is deleted without
  // the person's tap.
  static const _askStep = 500 << 20;

  Future<void> _offerToFreeSpace(RepositoryProvider provider, Repository repo) async {
    final info = await provider.withRepoFolder(repo, (path) => Isolate.run(() {
          final folders = listBackupFolders(path);
          final total = folders.fold<int>(0, (n, f) => n + f.bytes);
          final mark = File('$path/$kFullBackupsFolder/.size_asked');
          final asked = mark.existsSync() ? int.tryParse(mark.readAsStringSync().trim()) ?? 0 : 0;
          final monthAgo = DateTime.now().subtract(const Duration(days: 30));
          final old = [
            for (final f in folders.where((f) => f.phoneOnly))
              if (fullBackupDate(f.name) case final d?
                  when d.isBefore(monthAgo) && !File('$path/${f.relPath}/.localsync_asked').existsSync())
                f
          ];
          return (folders, total, asked, old);
        }));
    if (info == null || !mounted) return;
    final (folders, total, asked, old) = info;
    provider.setBackupBytes(total);
    if (total < _askStep || total < asked + _askStep) {
      if (old.isNotEmpty) await _offerOldCopies(provider, repo, old);
      return;
    }
    final what = repo.syncMode == SyncMode.genericFolder ? 'files' : 'notes';
    final answer = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: kSurface,
        title: Row(children: [
          Icon(Icons.sd_storage_outlined, color: Colors.amber, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Backups use ${formatBytes(total)}',
                style: TextStyle(color: kStar, fontSize: 17)),
          ),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in [
              'Backups: ${folders.length} safety copies LocalSync made on this phone',
              'Your $what: not touched, also kept in the sync history',
              'iPhone Storage: shows this space under Obsidian, not LocalSync',
              'Obsidian app: do not delete it to free space, that removes your $what from this phone',
              'Later: LocalSync -> ⋮ -> Backups -> Delete all',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('•  ', style: TextStyle(color: kTextMid, fontSize: 14.5)),
                  Expanded(child: Text(line, style: TextStyle(color: kTextMid, fontSize: 14.5, height: 1.35))),
                ]),
              ),
            TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: () => launchUrl(Uri.parse('https://kworld.space/localsync/help#backups-clean-up'),
                  mode: LaunchMode.externalApplication),
              child: Text('Help: freeing phone space', style: TextStyle(color: kBlue, fontSize: 14.5)),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, 'later'),
              child: Text('LATER', style: TextStyle(color: kTextDim))),
          TextButton(
              onPressed: () => Navigator.pop(c, 'see'),
              child: Text('SEE BACKUPS', style: TextStyle(color: kStar))),
          TextButton(
              onPressed: () => Navigator.pop(c, 'delete'),
              child: Text('DELETE ALL',
                  style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    await provider.withRepoFolder(repo, (path) {
      try {
        Directory('$path/$kFullBackupsFolder').createSync(recursive: true);
        File('$path/$kFullBackupsFolder/.size_asked')
            .writeAsStringSync('${answer == 'delete' ? 0 : total}\n');
      } catch (_) {}
    });
    if (!mounted) return;
    if (answer == 'see') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => BackupsScreen(repo: repo)));
    } else if (answer == 'delete') {
      await provider.withRepoFolder(repo, (path) => deleteBackupFolders(path, folders));
      provider.setBackupBytes(0);
      // Backups from before 2026-09-30 could sit in the synced LocalSync folder: send the removal to the desktop too.
      if (folders.any((f) => !f.relPath.startsWith('.')) && repo.id != null) {
        await provider.pushRepository(repo.id!, commitMessage: 'Delete LocalSync backups', confirmed: true);
      }
    }
  }

  /// 2026-11-13 owner: copies older than 30 days, once everything has synced (this runs right after a sync), are offered
  /// for deletion with one tap. Asked once per copy (.localsync_asked next to it).
  Future<void> _offerOldCopies(RepositoryProvider provider, Repository repo, List<BackupFolder> old) async {
    final bytes = old.fold<int>(0, (n, f) => n + f.bytes);
    final what = repo.syncMode == SyncMode.genericFolder ? 'files' : 'notes';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: kSurface,
        title: Row(children: [
          Icon(Icons.history, color: kStar, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(old.length == 1 ? 'Old backup, ${formatBytes(bytes)}' : 'Old backups, ${formatBytes(bytes)}',
                style: TextStyle(color: kStar, fontSize: 17)),
          ),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in [
              'Backups: ${old.length == 1 ? '1 copy' : '${old.length} copies'} over 30 days old',
              'Your $what: synced, not touched',
              'Delete: frees ${formatBytes(bytes)} on this phone',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('•  ', style: TextStyle(color: kTextMid, fontSize: 14.5)),
                  Expanded(child: Text(line, style: TextStyle(color: kTextMid, fontSize: 14.5, height: 1.35))),
                ]),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text('KEEP', style: TextStyle(color: kTextDim))),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text('DELETE', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    await provider.withRepoFolder(repo, (path) {
      for (final f in old) {
        if (ok == true) {
          deleteFullBackup(path, f);
        } else {
          try {
            File('$path/${f.relPath}/.localsync_asked').writeAsStringSync('KEEP\n');
          } catch (_) {}
        }
      }
    });
    if (ok == true) provider.setBackupBytes(provider.backupBytes - bytes);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
