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
  }

  @override
  void dispose() {
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
    if (state == AppLifecycleState.resumed) _gatedAutoSync();
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
    if (provider.pendingQuickAction != null) return;
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
