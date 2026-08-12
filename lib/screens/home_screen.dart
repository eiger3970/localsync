// screens/home_screen.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../constants.dart';
import '../models/repository.dart';
import '../services/repository_provider.dart';
import '../services/sync_service.dart';
import '../widgets/action_gif.dart';
import '../widgets/sparkle_background.dart';
import 'commit_screen.dart';
import 'linking_screen.dart';
import 'pairing_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // 2026-08-17: "PKM_vault needs to be centered" - moved from
        // actions (left-aligned, hugging the title) into the title
        // itself as a Row with an Expanded+Center around it, so it
        // sits centered in the space between SYNCLOCAL and the
        // kebab/tick icons rather than immediately after the title.
        title: Row(
          children: [
            const Text('SYNCLOCAL'),
            Expanded(
              child: Center(
                child: Consumer<RepositoryProvider>(
                  builder: (_, provider, __) => provider.repos.isEmpty
                      ? const SizedBox.shrink()
                      : _AppBarRepoStatus(
                          repo: provider.repos.first,
                          onTap: () => _runAndShow(context,
                              provider.pullRepository(provider.repos.first.id!)),
                        ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          // Fixed 2026-08-09: two bare icon buttons (key, phone) with only
          // a long-press tooltip for explanation - on iOS a tap doesn't
          // show the tooltip at all, so neither icon was actually self-
          // explanatory at a glance. User's own words: "Key and phone
          // image, why, if yes, make clearer." Consolidated into one menu
          // with real text labels - still fully reachable (re-pairing a
          // new phone, or linking an additional vault, are both genuine
          // ongoing needs, not first-run-only), just not two unexplained
          // icons sitting permanently in the app bar.
          // 2026-08-15: gained the repo-scoped actions (commit with a
          // typed message, auto/manual toggle, remove) that used to
          // live in each tile's own trailing kebab - per explicit
          // direction, that kebab is gone entirely now that the whole
          // tile is tappable-to-sync and the gif gesture zone below the
          // list handles pull/push. Single-repo assumption throughout
          // (operates on provider.repos.first): this app is one phone,
          // one vault in practice (ADD MANUALLY, the only path that
          // could add a second, was removed 2026-08-15) - revisit if
          // multi-repo ever becomes a real use case.
          Consumer<RepositoryProvider>(
            builder: (_, provider, __) => PopupMenuButton<String>(
              color: kSurface,
              icon: const Icon(Icons.more_vert, color: kGreen, size: 22),
              onSelected: (v) {
                if (v == 'pair') _openPairing(context);
                if (v == 'link') _openLinking(context);
                final repo = provider.repos.isEmpty ? null : provider.repos.first;
                if (repo == null) return;
                if (v == 'commit') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => CommitScreen(repo: repo)),
                  );
                }
                if (v == 'toggle_auto') provider.toggleAutoSync(repo.id!);
                if (v == 'delete') _confirmDelete(context, provider, repo);
              },
              // 2026-08-11: labels alone still drew "why are these
              // needed?" on real device review - added a one-line reason
              // under each so the menu explains itself without relying on
              // a tooltip (already known not to fire on iOS tap, see the
              // fix note above) or a chat explanation the user won't have
              // open next time they wonder.
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'pair',
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: const [
                      Icon(Icons.vpn_key_outlined, color: kStar, size: 18),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Pair with desktop',
                                style: TextStyle(color: kStar, fontSize: 14)),
                            Text('New phone, or lost connection',
                                style:
                                    TextStyle(color: kTextMid, fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'link',
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(Icons.phone_iphone, color: kStar, size: 18),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Set up a $kContainerName',
                                style: TextStyle(color: kStar, fontSize: 14)),
                            Text('Link another $kContainerName to this phone',
                                style:
                                    TextStyle(color: kTextMid, fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (provider.repos.isNotEmpty) ...[
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'commit',
                    child: Text('Commit with message...',
                        style: TextStyle(color: kStar, fontSize: 14)),
                  ),
                  // 2026-08-18: "I can't think of a solution to a
                  // desktop mouseover info feature for the phone
                  // finger controls" - no hover tooltips on a touch
                  // screen, so same fix as the Pair/Set-up items above:
                  // a persistent one-line explainer under the label
                  // instead of relying on a tooltip that can't fire.
                  PopupMenuItem(
                    value: 'toggle_auto',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          provider.repos.first.autoSync
                              ? 'Switch to manual'
                              : 'Switch to auto',
                          style: const TextStyle(color: kStar, fontSize: 14),
                        ),
                        Text(
                          provider.repos.first.autoSync
                              ? 'Stop pulling automatically when the app opens'
                              : 'Pull automatically every time the app opens',
                          style:
                              const TextStyle(color: kTextMid, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Remove',
                        style:
                            TextStyle(color: Colors.redAccent, fontSize: 14)),
                  ),
                ],
              ],
            ),
          ),
          Consumer<RepositoryProvider>(
            builder: (_, p, __) => Padding(
              padding: const EdgeInsets.only(right: 16),
              child: _StatusIcon(repos: p.repos),
            ),
          ),
        ],
      ),
      // 2026-08-15: real device feedback - "huge black space for
      // numerous repositories" below the list, doing nothing. Tile
      // stopped being a scrolling list that fills the whole body
      // (shrink-wrapped instead, matches the one-repo-in-practice
      // reality) and the freed space below it became the pull/push
      // gesture zone. Per explicit direction: tile's own trailing
      // refresh icon + kebab are gone (the tap-target-size fix from
      // earlier this session is moot now - the whole row is the tap
      // target), those actions moved to the top-bar kebab above or the
      // gif swipes below.
      body: Consumer<RepositoryProvider>(
        builder: (_, provider, __) {
          if (provider.loading) {
            return const Center(
              child: CircularProgressIndicator(color: kGreen, strokeWidth: 1),
            );
          }
          // 2026-08-17: "why is page 1 necessary, can't page 2 do all
          // that?" - it couldn't, because page 1 (this empty state)
          // and page 2 (LinkingScreen's own _IdleView) were both a
          // drag-to-connect gesture, back to back - page 1's drag did
          // nothing except open page 2, which then made the user drag
          // again before anything real happened. Removed entirely:
          // straight to LinkingScreen (still titled PKM VAULT SETUP,
          // still requires its own real drag to actually start
          // pairing - that gesture is genuine, page 1's was not).
          // pushReplacement, not push - backing out of setup with zero
          // repos configured should land on an actual empty state, not
          // instantly redirect right back into setup again.
          if (provider.repos.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) {
                Navigator.pushReplacement(context,
                    MaterialPageRoute(builder: (_) => const LinkingScreen()));
              }
            });
            return const SizedBox.shrink();
          }
          final repo = provider.repos.first;
          // 2026-08-17: the repo tile's summary row moved into the app
          // bar (_AppBarRepoStatus above) - nothing left to show here
          // except the gesture zone, which now gets the full body.
          return _SyncGestureZone(
            onPull: () =>
                _runAndShow(context, provider.pullRepository(repo.id!)),
            onPush: () =>
                _runAndShow(context, provider.pushRepository(repo.id!)),
          );
        },
      ),
    );
  }

  // 2026-08-16: "Push, is this auto committing an auto timestamp... I
  // can't see?" - the result (including the actual commit message on
  // a real push, see sync_service.dart) is otherwise invisible once
  // the action finishes. A brief SnackBar is enough to confirm it
  // without adding a permanent status field to Repository for what's
  // fundamentally a one-off confirmation, not state worth persisting.
  Future<void> _runAndShow(BuildContext context, Future<SyncResult?> op) async {
    final result = await op;
    if (!context.mounted || result == null) return;
    final text = switch (result) {
      SyncOk(:final message)  => message,
      SyncNoChanges()          => 'Nothing to sync',
      SyncConflict()           => 'Conflict - resolve on desktop then sync again',
      SyncFailed(:final diagnosis) => diagnosis,
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
    );
  }

  void _openPairing(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const PairingScreen(
            desktopUser: 'rapi5',
            desktopIp: '172.20.10.11',
          ),
        ),
      );

  void _openLinking(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LinkingScreen()),
      );

  Future<void> _confirmDelete(
    BuildContext context,
    RepositoryProvider provider,
    Repository repo,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('Remove repository',
            style: TextStyle(color: kStar, fontSize: 17)),
        content: Text(
          'Remove "${repo.name}"? Files are not deleted.',
          style: const TextStyle(color: kTextMid, fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: kTextDim, fontSize: 15)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove',
                style: TextStyle(color: Colors.redAccent, fontSize: 15)),
          ),
        ],
      ),
    );
    if (confirmed == true && repo.id != null) {
      await provider.removeRepository(repo.id!);
    }
  }
}

// ── Pull/push gesture zone ────────────────────────────────────────────────────
//
// 2026-08-15: fills the "huge black space" that used to sit empty below
// the repo list. Pull and push are real, separate operations now (see
// sync_service.dart's header comment) - the gifs and opposite swipe
// directions aren't just decoration over one shared function anymore.
class _SyncGestureZone extends StatelessWidget {
  final Future<void> Function() onPull;
  final Future<void> Function() onPush;
  const _SyncGestureZone({required this.onPull, required this.onPush});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _GifSwipeTrigger(
            assetPath: 'assets/gifs/git_pull.gif',
            caption: 'PULL',
            swipeDown: true,
            // 2026-08-17: "a lot of black space between PULL and
            // PUSH, can the gifs be enlarged 30%?" - another 30% up
            // from last round (90 -> 117 -> 152 -> 198 for pull;
            // 90 -> 117 -> 152 for push, catching up).
            gifHeight: 198,
            alignTop: true,
            onConfirm: onPull,
          ),
        ),
        Expanded(
          child: _GifSwipeTrigger(
            assetPath: 'assets/gifs/git_push.gif',
            caption: 'PUSH',
            swipeDown: false,
            gifHeight: 152,
            onConfirm: onPush,
          ),
        ),
      ],
    );
  }
}

class _GifSwipeTrigger extends StatefulWidget {
  final String assetPath;
  final String caption;
  final bool swipeDown; // true = swipe down triggers, false = swipe up
  final double gifHeight;
  final bool alignTop;
  final Future<void> Function() onConfirm;
  const _GifSwipeTrigger({
    required this.assetPath,
    required this.caption,
    required this.swipeDown,
    required this.gifHeight,
    this.alignTop = false,
    required this.onConfirm,
  });

  @override
  State<_GifSwipeTrigger> createState() => _GifSwipeTriggerState();
}

class _GifSwipeTriggerState extends State<_GifSwipeTrigger> {
  static const _threshold = 56.0;
  static const _maxDrag = 140.0;
  // 2026-08-16: the play/idle + minimum-2000ms/no-max/reset-safety
  // timing logic moved into the shared ActionGif widget (lib/widgets/)
  // - this class now owns only gesture detection (drag tracking),
  // calling trigger() on it instead of duplicating that logic here.
  final _gifKey = GlobalKey<ActionGifState>();
  double _drag = 0;

  bool get _playing => _gifKey.currentState?.isPlaying ?? false;

  void _onUpdate(double delta) {
    if (_playing) return;
    setState(() {
      _drag = widget.swipeDown
          ? (_drag + delta).clamp(0.0, _maxDrag)
          : (_drag + delta).clamp(-_maxDrag, 0.0);
    });
  }

  void _onEnd() {
    if (_playing) return;
    final reached = (widget.swipeDown ? _drag : -_drag) >= _threshold;
    setState(() => _drag = 0);
    if (reached) _gifKey.currentState?.trigger(widget.onConfirm);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragUpdate: (d) => _onUpdate(d.delta.dy),
      onVerticalDragEnd: (_) => _onEnd(),
      child: Container(
        width: double.infinity,
        color: kVoid,
        // 2026-08-19: "rather than the whole page, indicate the user is
        // to PULL or PUSH, so just have magic stars around the words
        // PULL and PUSH" - the full-zone SparkleBackground (2026-08-18)
        // hinted at the gif art too, which isn't itself the actionable
        // hint (the caption is what tells you which gesture this half
        // is). Sparkles now scope to just the caption below.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: widget.alignTop
              // 2026-08-16: "Pull can be higher, seeing it will
              // be pulled from top to down" - pull sits toward
              // the top of its half instead of dead center,
              // matching the "content flows down from above"
              // mental model; push stays centered.
              ? MainAxisAlignment.start
              : MainAxisAlignment.center,
          children: [
            if (widget.alignTop) const SizedBox(height: 12),
            Transform.translate(
              offset: Offset(0, _drag),
              child: ActionGif(
                key: _gifKey,
                assetPath: widget.assetPath,
                height: widget.gifHeight,
              ),
            ),
            const SizedBox(height: 14),
            Stack(
              alignment: Alignment.center,
              children: [
                if (!_playing) const Positioned.fill(child: SparkleBackground()),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(widget.caption,
                      style: const TextStyle(
                          color: kTextMid,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
// ── Spinning sync icon ─────────────────────────────────────────────────────────

class _SpinningSync extends StatefulWidget {
  const _SpinningSync();

  @override
  State<_SpinningSync> createState() => _SpinningSyncState();
}

class _SpinningSyncState extends State<_SpinningSync>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => Transform.rotate(
        angle: _ctrl.value * 2 * math.pi,
        child: child,
      ),
      child: const Icon(Icons.sync, color: kGreen, size: 22),
    );
  }
}

// 2026-08-17: relocated from the removed _MetaText - the persistent,
// tappable full-error view is real functionality, not just tile
// decoration, so it moved into _AppBarRepoStatus rather than being
// discarded along with the tile row it used to live in.
void _showFullError(BuildContext context, String fullError) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: kSurface,
      title: const Text('Sync error',
          style: TextStyle(color: kStar, fontSize: 17)),
      content: SingleChildScrollView(
        child: Text(fullError,
            style:
                const TextStyle(color: kTextMid, fontSize: 14, height: 1.6)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close',
              style: TextStyle(color: kGreen, fontSize: 15)),
        ),
      ],
    ),
  );
}

// ── Auto/manual badge ──────────────────────────────────────────────────────────

class _AutoBadge extends StatelessWidget {
  final bool autoSync;
  const _AutoBadge({required this.autoSync});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: autoSync ? kGreen.withOpacity(0.15) : kBorder,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        autoSync ? 'AUTO' : 'MANUAL',
        style: TextStyle(
          color: autoSync ? kGreen : kTextDim,
          fontSize: 8,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ── Status dot ─────────────────────────────────────────────────────────────────

class _StatusDot extends StatelessWidget {
  final SyncStatus status;
  const _StatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      SyncStatus.ok => kGreen,
      SyncStatus.syncing => Colors.amber,
      SyncStatus.error => Colors.redAccent,
      SyncStatus.idle => kTextDim,
    };
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

// ── Top-right status icon ──────────────────────────────────────────────────────

class _StatusIcon extends StatelessWidget {
  final List<Repository> repos;
  const _StatusIcon({required this.repos});

  @override
  Widget build(BuildContext context) {
    if (repos.isEmpty) return const SizedBox.shrink();
    final hasError = repos.any((r) => r.status == SyncStatus.error);
    final hasSyncing = repos.any((r) => r.status == SyncStatus.syncing);
    final allOk = repos.every((r) => r.status == SyncStatus.ok);

    if (hasSyncing)
      return const Icon(Icons.sync, color: Colors.amber, size: 22);
    if (hasError)
      return const Icon(Icons.error_outline, color: Colors.redAccent, size: 22);
    if (allOk)
      return const Icon(Icons.check_circle_outline, color: kGreen, size: 22);
    return const Icon(Icons.circle_outlined, color: kTextDim, size: 22);
  }
}

// 2026-08-17: was a _MetaText instance method - extracted to top-level
// so _AppBarRepoStatus can share it instead of duplicating.
String _timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

// ── App-bar repo status ───────────────────────────────────────────────────────
//
// 2026-08-17: "can row 2 PKM_vault AUTO synced just now be moved to
// row 1, right of SYNCLOCAL and left of the kebab icon and green
// tick?" - the repo tile's summary moved into the app bar itself, and
// the separate ListView row it used to live in is gone (see the body
// builder below). Tap still triggers a pull, same as the row did.
class _AppBarRepoStatus extends StatelessWidget {
  final Repository repo;
  final VoidCallback onTap;
  const _AppBarRepoStatus({required this.repo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isSyncing = repo.status == SyncStatus.syncing;
    // Fixed 2026-08-09, relocated here 2026-08-17: full error text
    // (diagnosis + resolution + raw exception) was getting truncated
    // to one line with no way to see the rest - tapping while an
    // error is active shows the full dialog instead of triggering
    // another pull, which would just fail again the same way.
    final hasError = repo.status == SyncStatus.error && repo.lastError != null;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        if (hasError) {
          _showFullError(context, repo.lastError!);
        } else {
          onTap();
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                isSyncing
                    ? const _SpinningSync()
                    : _StatusDot(status: repo.status),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    repo.name,
                    style: const TextStyle(
                        color: kStar, fontSize: 13, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                _AutoBadge(autoSync: repo.autoSync),
              ],
            ),
            if (hasError)
              Text(
                repo.lastError!.split('\n').first,
                style: const TextStyle(color: Colors.redAccent, fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            else if (isSyncing)
              Text(repo.syncPhase.label,
                  style: const TextStyle(color: kTextMid, fontSize: 10))
            else if (repo.lastSync != null)
              Text('synced ${_timeAgo(repo.lastSync!)}',
                  style: const TextStyle(color: kTextMid, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

