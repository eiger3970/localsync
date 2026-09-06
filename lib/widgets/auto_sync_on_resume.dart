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
import '../services/repository_provider.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoSync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _autoSync();
  }

  Future<void> _autoSync() async {
    // 2026-08-21's own _run()/_runLocked() already serializes concurrent
    // push/pulls per repo id (awaits any prior in-flight one first) -
    // this flag is just to skip scheduling a redundant second attempt
    // from rapid resume/foreground churn, not real locking.
    if (_syncing || !mounted) return;
    final provider = context.read<RepositoryProvider>();
    final repo = provider.selectedRepo;
    if (repo?.id == null) return;
    _syncing = true;
    try {
      // Push first - carries forward any real local edit before
      // anything else gets a chance to touch it - then pull, same
      // order a manual "catch up both ways" session would use.
      await provider.pushRepository(repo!.id!);
      if (!mounted) return;
      await provider.pullRepository(repo.id!);
    } catch (_) {
      // Best-effort only - a real failure here is left for the user's
      // own next manual sync to surface properly, not narrated here.
    } finally {
      _syncing = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
