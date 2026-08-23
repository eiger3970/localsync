// screens/home_screen.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../constants.dart';
import '../models/repository.dart';
import '../services/device_name.dart';
import '../services/repository_provider.dart';
import '../services/sync_service.dart';
import '../widgets/diag_card.dart';
import '../widgets/gif_swipe_trigger.dart';
import '../widgets/sync_confirm_dialog.dart';
import 'commit_screen.dart';
import 'conflicts_screen.dart';
import 'linking_screen.dart';
import '../features/linking/linking_controller.dart';
import 'pairing_screen.dart';
import 'security_info_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // 2026-08-17: "PKM_vault needs to be centered" - moved from
        // actions (left-aligned, hugging the title) into the title
        // itself as a Row with an Expanded+Center around it, so it
        // sits centered in the space between LOCALSYNC and the
        // kebab/tick icons rather than immediately after the title.
        title: Row(
          children: [
            // 2026-08-21: "Logo placement can go in top left of
            // running/opened app" - the icon artwork only ever showed
            // as the home-screen icon before; a small copy of it now
            // sits in-app too, top-left of the bar.
            // 2026-08-14: replaced the separate icon+"LOCALSYNC" text
            // pair with a single combined wordmark graphic (the circle
            // logo sits inside the "O" of LOCALSYNC in the source art).
            Image.asset('assets/icon/logo_word_with_circle.png', height: 16),
            Expanded(
              child: Center(
                child: Consumer<RepositoryProvider>(
                  builder: (_, provider, __) => provider.repos.isEmpty
                      ? const SizedBox.shrink()
                      : _AppBarRepoStatus(
                          repo: provider.selectedRepo!,
                          allRepos: provider.repos,
                          onTap: () => _runAndShow(context,
                              ({bool confirmed = false}) => provider.pullRepository(
                                  provider.selectedRepo!.id!, confirmed: confirmed),
                              repo: provider.selectedRepo),
                          onSelect: provider.selectRepo,
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
          // list handles pull/push.
          // 2026-08-20: "Multi repo needed on app" - these actions now
          // target provider.selectedRepo (switchable via the app-bar
          // dropdown, see _AppBarRepoStatus) instead of always
          // repos.first - real multi-vault support, not just the data
          // model tolerating it.
          //
          // 2026-08-21: real bug, live, two rounds - "the drop down
          // arrow is exactly behind the kebab icon." The earlier fix
          // (padding on the dropdown itself, plus a SizedBox after it
          // inside _AppBarRepoStatus's own Row) didn't help, because
          // that spacing lives inside `title`, and Flutter's AppBar
          // puts zero native gap between `title` and `actions` - if
          // the title's content is centered right up against that
          // boundary, internal trailing padding never creates a real
          // visual gap from whatever `actions` starts with. Forcing a
          // real gap from the `actions` side instead is unambiguous
          // regardless of how the title's own centering math resolves.
          const SizedBox(width: 14),
          Consumer<RepositoryProvider>(
            builder: (_, provider, __) => PopupMenuButton<String>(
              color: kSurface,
              icon: Icon(Icons.more_vert, color: kGreen, size: 22),
              onSelected: (v) {
                if (v == 'pair') _openPairing(context);
                if (v == 'link') _openLinking(context);
                if (v == 'about') _showAbout(context);
                if (v == 'device_name') _editDeviceName(context, provider);
                if (v == 'settings') {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()));
                }
                final repo = provider.selectedRepo;
                if (repo == null) return;
                if (v == 'commit') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => CommitScreen(repo: repo)),
                  );
                }
                if (v == 'toggle_auto') provider.toggleAutoSync(repo.id!);
                if (v == 'conflicts') {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => ConflictsScreen(repo: repo)));
                }
                if (v == 'delete') _confirmDelete(context, provider, repo);
              },
              // 2026-08-18: full menu cleanup per explicit list - one
              // flat alphabetical order (About, Conflicts, Connection,
              // Device name, Pair, Pull, Vault), no dividers. Only
              // exception: Commit stays pinned first since it's what
              // gets tapped most once set up is done - a stated reason
              // to deviate from alphabetical, not an arbitrary one (see
              // house naming rule). One-line explainer under each label
              // still stands in for a hover tooltip, which doesn't fire
              // on iOS tap.
              itemBuilder: (_) {
                final hasRepo = provider.repos.isNotEmpty;
                return [
                  if (hasRepo)
                    const PopupMenuItem(
                      value: 'commit',
                      child: _MenuRow(
                        icon: Icons.edit_note,
                        label: 'Commit with message...',
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'about',
                    child: _MenuRow(icon: Icons.info_outline, label: 'About'),
                  ),
                  if (hasRepo)
                    const PopupMenuItem(
                      value: 'conflicts',
                      child: _MenuRow(
                        icon: Icons.compare_arrows,
                        label: 'Conflicts',
                        subtitle: 'Files with unresolved sync conflicts',
                      ),
                    ),
                  if (hasRepo)
                    const PopupMenuItem(
                      value: 'delete',
                      child: _MenuRow(
                        icon: Icons.link_off,
                        iconColor: Colors.redAccent,
                        label: 'Connection of sync - remove',
                        labelColor: Colors.redAccent,
                      ),
                    ),
                  // 2026-08-18: device-level, not repo-scoped - used as
                  // the git commit author so a sync conflict can say who
                  // made a change, not just when (see sync_service.dart's
                  // _signatureFor). Placeholder in the explainer, not a
                  // real/pseudonym example - names never go in app UI text.
                  const PopupMenuItem(
                    value: 'device_name',
                    child: _MenuRow(
                      icon: Icons.smartphone,
                      label: 'Device name',
                      subtitle: 'Shown in sync conflicts',
                    ),
                  ),
                  PopupMenuItem(
                    value: 'pair',
                    // 2026-08-16: "can the key be pairing_phone_key.svg" -
                    // real key asset from the pairing gesture, not a
                    // stand-in Material icon like the rest of this menu -
                    // this one's kept custom since it's already built and
                    // matches the pairing screen's own theme.
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SvgPicture.asset(
                          'assets/pairing/pairing_phone_key.svg',
                          width: 18,
                          colorFilter:
                              ColorFilter.mode(kStar, BlendMode.srcIn),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Pair with desktop',
                                  style:
                                      TextStyle(color: kStar, fontSize: 14)),
                              Text('New phone, or lost connection',
                                  style: TextStyle(
                                      color: kTextMid, fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 2026-08-18: renamed from Switch to manual/auto -
                  // "Pull manually"/"Pull automatically" says the actual
                  // action, not a generic mode-switch label.
                  if (hasRepo)
                    PopupMenuItem(
                      value: 'toggle_auto',
                      child: _MenuRow(
                        // 2026-08-21: real feedback, live - "Pull
                        // manually is not a hand... I'll create the svg
                        // for this" - Icons.swipe_down_alt didn't read
                        // as a hand on-device, user is building a
                        // custom SVG for this themselves. Reverted to
                        // the original icon in the meantime rather than
                        // guessing at another Material substitute.
                        icon: Icons.sync,
                        label: provider.selectedRepo!.autoSync
                            ? 'Pull manually'
                            : 'Pull automatically',
                        // 2026-08-21: real feedback, live - "change to:
                        // stop auto pull on app open" - shorter, same
                        // meaning.
                        subtitle: provider.selectedRepo!.autoSync
                            ? 'Stop auto pull on app open'
                            : 'Pull automatically every time the app opens',
                      ),
                    ),
                  // 2026-08-20: real user feedback - "this is difficult
                  // for users, I need to build this in." Desktop IP
                  // drifts (USB tether vs hotspot vs plain DHCP
                  // reassignment) and used to be a build-time constant.
                  // Now a real screen (settings_screen.dart) - also
                  // houses Bare repo path, added for genuine multi-repo
                  // support (bareRepoPath was likewise a build-time
                  // constant, meaning a second vault could never target
                  // a different bare repo than the first).
                  const PopupMenuItem(
                    value: 'settings',
                    child: _MenuRow(
                      // 2026-08-21: real feedback, live - "a wrench is
                      // smaller and minimal, taking less screen space
                      // and attention" than a cog.
                      icon: Icons.build_outlined,
                      label: 'Settings',
                      // 2026-08-21: real feedback, live - reordered
                      // alphabetically (Git before IP), same request
                      // applied to the Settings screen's own field
                      // order. Follow-up, same day: the natural word-
                      // wrap split "IP address - desktop" itself across
                      // both lines ("...IP address -" / "desktop"). A
                      // literal newline after the comma forces the
                      // break to always land there instead, keeping
                      // "IP address - desktop" whole on its own line.
                      // 2026-08-21: real feedback, live - comma removed,
                      // the line break already separates the two.
                      subtitle: 'Git bare repo path\nIP address - desktop',
                    ),
                  ),
                  PopupMenuItem(
                    value: 'link',
                    child: _MenuRow(
                      icon: Icons.phone_iphone,
                      label: provider.repos.isEmpty
                          ? 'Vault - set up'
                          : 'Vault - add another',
                      subtitle: provider.repos.isEmpty
                          ? 'Link a $kContainerName to this phone'
                          : 'Link another $kContainerName to this phone',
                    ),
                  ),
                ];
              },
            ),
          ),
          Consumer<RepositoryProvider>(
            builder: (_, p, __) => Padding(
              padding: const EdgeInsets.only(right: 16),
              // 2026-08-23: real feature request, live - was purely
              // decorative (tapping it did nothing). Now opens the
              // security explainer screen - same tap target, real
              // action behind it.
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SecurityInfoScreen()),
                ),
                child: _StatusIcon(repos: p.repos),
              ),
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
      // 2026-08-21: "add real flags around, like a Fortnite skin
      // around the edges, but so you can still see and operate the
      // functions" - home screen was the real test case, per explicit
      // scope confirmation, before rolling this out further.
      // 2026-08-22: rolled out - main.dart's MaterialApp.builder now
      // wraps every screen the same way (FlagFrame + FlagBackdrop),
      // not just this one body. Removed here to avoid double-applying
      // it.
      body: Consumer<RepositoryProvider>(
        builder: (_, provider, __) {
          if (provider.loading) {
            return Center(
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
          final repo = provider.selectedRepo!;
          // 2026-08-19: the auto-sync-on-launch pull (RepositoryProvider
          // ._init()) runs before this screen even exists, so it can't
          // navigate directly the way _runAndShow's manual-pull handler
          // below does - it just leaves a repo id here instead. Same
          // post-frame-callback pattern as the empty-repos redirect
          // above. Cleared immediately so a later unrelated rebuild
          // (e.g. selecting a different repo) doesn't re-trigger it.
          final pendingId = provider.pendingConflictRepoId;
          if (pendingId != null) {
            final pendingRepo = provider.repos
                .where((r) => r.id == pendingId)
                .cast<Repository?>()
                .firstWhere((_) => true, orElse: () => null);
            // clearPendingConflict() calls notifyListeners() - must not
            // run synchronously mid-build (Flutter forbids triggering a
            // rebuild while one is already in progress), so both it and
            // the navigation itself wait for the frame to finish.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              provider.clearPendingConflict();
              if (pendingRepo != null && context.mounted) {
                Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ConflictsScreen(repo: pendingRepo)));
              }
            });
          }
          // 2026-08-17: the repo tile's summary row moved into the app
          // bar (_AppBarRepoStatus above) - nothing left to show here
          // except the gesture zone, which now gets the full body.
          // 2026-08-20: acts on the selected repo (see app-bar
          // dropdown), not always the first one, now that multiple can
          // genuinely exist.
          return _SyncGestureZone(
            onPull: () => _runAndShow(context,
                ({bool confirmed = false}) =>
                    provider.pullRepository(repo.id!, confirmed: confirmed),
                repo: repo),
            onPush: () => _runAndShow(context,
                ({bool confirmed = false}) =>
                    provider.pushRepository(repo.id!, confirmed: confirmed)),
          );
        },
      ),
    );
  }

  // 2026-08-20: real bug, found live - this used to hardcode
  // '172.20.10.11' independently of LinkingController.desktopIp, so a
  // user who'd corrected their address via the Desktop IP setting
  // below would still hit this stale value re-pairing. Reads the live
  // controller instead of a second, disconnected copy.
  void _openPairing(BuildContext context) {
    final ctrl = context.read<LinkingController>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PairingScreen(
          desktopUser: ctrl.desktopUser,
          desktopIp: ctrl.desktopIp,
        ),
      ),
    );
  }

  // 2026-08-18: "Add another vault" used to land straight on a stale
  // failure screen from whatever the PREVIOUS linking attempt left
  // behind - LinkingController is an app-root singleton (same class of
  // bug already fixed once tonight for stale pairing state), so simply
  // navigating here without resetting it first just displays leftover
  // state, not a fresh attempt. Reset before every navigation in.
  void _openLinking(BuildContext context) {
    context.read<LinkingController>().reset();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LinkingScreen()),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    RepositoryProvider provider,
    Repository repo,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kSurface,
        // 2026-08-19: "what does Remove remove, a vault, a repository,
        // what?" - "repository" is developer jargon (same class of fix
        // as "picker" -> "Files" elsewhere in this app), and the old
        // body ("Files are not deleted") said what doesn't happen
        // without naming what does. Now explicit: this removes the
        // sync connection only, names the actual vault folder by its
        // real name, and says directly that it stays untouched.
        title: Text('Remove sync connection',
            style: TextStyle(color: kStar, fontSize: 17)),
        content: Text(
          'This unlinks "${repo.localPath.split('/').last}" from your desktop '
          '$kGenericAppLabel $kContainerName. The $kContainerName and its '
          'files stay on this phone.',
          style: TextStyle(color: kTextMid, fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
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

  // 2026-08-18: pre-fills with whatever's already set (empty on first
  // use) rather than assuming - this is the identity that'll show up on
  // every future conflict, worth letting the user see/confirm the
  // current value, not just blindly overwrite it.
  Future<void> _editDeviceName(
    BuildContext context,
    RepositoryProvider provider,
  ) async {
    final saved = await provider.getDeviceName();
    // 2026-08-18: nothing saved yet -> pre-fill with the phone's own
    // name instead of a blank field, so the dialog shows what's
    // actually being used right now (see device_name.dart) rather than
    // looking unset when a real default is already in effect.
    final current = (saved != null && saved.trim().isNotEmpty)
        ? saved
        : await defaultDeviceName();
    if (!context.mounted) return;
    final ctrl = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kSurface,
        title: Text('Device name',
            style: TextStyle(color: kStar, fontSize: 17)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: kStar),
          decoration: const InputDecoration(hintText: "e.g. Ken's phone"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Cancel',
                style: TextStyle(color: kTextDim, fontSize: 15)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, ctrl.text.trim()),
            child: Text('Save',
                style: TextStyle(color: kStar, fontSize: 15)),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await provider.setDeviceName(name);
    }
  }
}

// ── Kebab menu row (icon + label + optional subtitle) ────────────────────────
//
// 2026-08-18: "all 8 points could have small svg images on the left of
// them" - only Pair/Vault had icons before, the rest looked bare next
// to them. Built-in Material icons, not custom SVG - same reasoning as
// the Conflicts screen's safety-icon row: no way to preview rendering
// before a sideload, and custom SVG art has a real history of needing
// several iterations to get right in this app. One shared row widget
// instead of repeating the icon+column layout 6 times.
class _MenuRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final Color? labelColor;
  final String? subtitle;
  // 2026-08-21: "skins" IAP - iconColor/labelColor used to default to
  // kStar directly in the parameter list, which only worked while
  // kStar was a compile-time const. Now that it's a getter (reads the
  // live selected palette), a default parameter value can't reference
  // it - Dart requires defaults to be constant expressions. Nullable
  // fields, resolved with `?? kStar` in build() instead, same effect.
  const _MenuRow({
    required this.icon,
    this.iconColor,
    required this.label,
    this.labelColor,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: iconColor ?? kStar, size: 18),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: TextStyle(color: labelColor ?? kStar, fontSize: 14)),
              if (subtitle != null)
                Text(subtitle!,
                    style: TextStyle(color: kTextMid, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
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
          child: GifSwipeTrigger(
            assetPath: 'assets/gifs/git_pull.gif',
            caption: 'PULL',
            swipeDown: true,
            // 2026-08-17: "a lot of black space between PULL and
            // PUSH, can the gifs be enlarged 30%?" - another 30% up
            // from last round (90 -> 117 -> 152 -> 198 -> 257 for pull;
            // 90 -> 117 -> 152 -> 198 for push, catching up).
            gifHeight: 257,
            alignTop: true,
            onConfirm: onPull,
          ),
        ),
        Expanded(
          child: GifSwipeTrigger(
            assetPath: 'assets/gifs/git_push.gif',
            caption: 'PUSH',
            swipeDown: false,
            gifHeight: 198,
            onConfirm: onPush,
          ),
        ),
      ],
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
      // 2026-08-20: real bug, live - "whilst syncing... pushed to the
      // right over the kebab icon." This icon was 22px against the
      // static _StatusDot's 7px - that extra 15px was exactly enough
      // to tip the row over during syncing specifically, even after
      // the vault-name width was capped. Shrunk to stay proportionate.
      child: Icon(Icons.sync, color: kGreen, size: 14),
    );
  }
}

// 2026-08-16: "Push, is this auto committing an auto timestamp... I
// can't see?" - the result (including the actual commit message on
// a real push, see sync_service.dart) is otherwise invisible once
// the action finishes. A brief SnackBar is enough to confirm it
// without adding a permanent status field to Repository for what's
// fundamentally a one-off confirmation, not state worth persisting.
// 2026-08-18: [op] takes a confirmed flag now instead of being an
// already-started Future, so a SyncNeedsConfirmation result can
// trigger a plain yes/no dialog and then re-run the exact same
// pull/push with confirmed:true - see sync_service.dart.
//
// 2026-08-19: [repo] is optional and only used for the new
// SyncOkWithConflicts case below - "way too convoluted, automate it"
// was the real complaint: a successful-looking pull gave no signal a
// conflict needed attention, so the only way to discover one was
// already knowing to check a menu with no badge on it (mapped out in
// this session's own mermaid flowchart). Push never produces this
// result (a conflict can only come from a pull's merge), so its call
// site below doesn't pass [repo] and this branch is simply
// unreachable there.
//
// 2026-08-21: moved out of HomeScreen (never used `this`/instance
// state) - _showFullError's new TRY AGAIN button needs to call this
// too, and it lives in a different private class (_AppBarRepoStatus),
// which can't reach a HomeScreen instance method.
Future<void> _runAndShow(
  BuildContext context,
  Future<SyncResult?> Function({bool confirmed}) op, {
  Repository? repo,
}) async {
  var result = await op();
  if (!context.mounted || result == null) return;
  if (result case SyncNeedsConfirmation()) {
    final proceed = await showSyncConfirmDialog(context, result);
    if (proceed != true || !context.mounted) return;
    result = await op(confirmed: true);
    if (!context.mounted || result == null) return;
  }
  // 2026-08-18: "make text size larger... on the main page 0's bottom
  // of screen message" - was relying on Flutter's default SnackBar
  // text theme (small, no explicit color), same underlying issue as
  // every other "too small and dark" fix tonight.
  // 2026-08-22: real feedback, live - "can that be centered rather
  // than left aligned on left bottom edge of screen" - SnackBar's
  // content has no built-in alignment option, it just left-aligns
  // whatever's given; wrapping in Center is the real fix, not a
  // textAlign tweak (textAlign alone wouldn't recentre the content
  // box itself, only text within it).
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: kSurface,
      content: Center(
        child: Text(syncResultMessage(result),
            textAlign: TextAlign.center,
            style: TextStyle(color: kStar, fontSize: 16)),
      ),
      duration: const Duration(seconds: 12),
    ),
  );
  if (result case SyncOkWithConflicts() when repo != null && context.mounted) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => ConflictsScreen(repo: repo)));
  }
}

// 2026-08-17: relocated from the removed _MetaText - the persistent,
// tappable full-error view is real functionality, not just tile
// decoration, so it moved into _AppBarRepoStatus rather than being
// discarded along with the tile row it used to live in.
//
// 2026-08-20: "show error in human language, how to fix it, then the
// error code verbose details - you've done this format with some
// errors but not others" - used to dump repo.lastError as one
// undifferentiated block of text (it was a pre-joined string at the
// time). Now takes the Repository directly and renders its three error
// fields through the same labeled DiagCard layout the setup flow's
// _FailedView already used (linking_screen.dart) - both places now
// look identical or a real inconsistency, not just this bug.
void _showFullError(BuildContext context, Repository repo) {
  // 2026-08-21: real bug, live - "I tapped TRY AGAIN but the text is
  // dead." HOW TO FIX IT's resolution strings all say "Tap TRY AGAIN"
  // (accurate in the linking flow, which really has that button) but
  // this dialog only ever had Close - no button the text's own
  // instruction referred to. Reads whichever action (push or pull)
  // actually failed (RepositoryProvider.lastActionWasPush, tracked at
  // call time) so TRY AGAIN here retries the SAME thing that failed,
  // not a guess.
  final provider = context.read<RepositoryProvider>();
  final wasPush = provider.lastActionWasPush(repo.id!);
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: kSurface,
      title: Text('Sync error',
          style: TextStyle(color: kStar, fontSize: 17)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DiagCard(
              label: 'WHAT HAPPENED',
              text: repo.lastError ?? 'Unknown error.',
              accent: Colors.redAccent,
            ),
            if (repo.lastErrorResolution != null) ...[
              const SizedBox(height: 12),
              DiagCard(
                label: 'HOW TO FIX IT',
                text: repo.lastErrorResolution!,
                accent: kGreen,
                icon: Icons.lightbulb_outline,
                bulleted: true,
              ),
            ],
            if (repo.lastErrorDebug != null) ...[
              const SizedBox(height: 12),
              DiagCard(
                label: 'RAW ERROR (TEMPORARY DIAGNOSTIC)',
                text: repo.lastErrorDebug!,
                accent: Colors.redAccent,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Close',
              style: TextStyle(color: kTextMid, fontSize: 15)),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            _runAndShow(
              context,
              ({bool confirmed = false}) => wasPush
                  ? provider.pushRepository(repo.id!, confirmed: confirmed)
                  : provider.pullRepository(repo.id!, confirmed: confirmed),
              repo: repo,
            );
          },
          child: Text('TRY AGAIN',
              style:
                  TextStyle(color: kGreen, fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
}

// ── About ──────────────────────────────────────────────────────────────────────
//
// 2026-08-20: "Kebab icon to have a credits at the bottom for: misc
// info, credits, version, other stuff apps need, disclaimer, promos,
// contact" - real content is user-owned (credits/contact/promo copy
// isn't something to invent), so those sections are left as clearly
// marked placeholders rather than guessed text. The one part that's
// fully real: "Open-source licenses" opens Flutter's own built-in
// license page, which auto-collects every dependency's license text
// (git2dart, provider, shared_preferences, etc.) - genuinely "stuff
// apps need" that a store listing/legal review expects, and needed
// zero new code to get right.
void _showAbout(BuildContext context) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: kSurface,
      title: Text('About',
          style: TextStyle(color: kStar, fontSize: 17)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('LocalSync',
                style: TextStyle(
                    color: kStar, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('v$kAppVersion',
                style: TextStyle(color: kTextMid, fontSize: 13)),
            const SizedBox(height: 12),
            Text('Local-first $kNoteAppName sync. No cloud. No subscription.',
                style: TextStyle(color: kTextMid, fontSize: 14, height: 1.6)),
            const SizedBox(height: 4),
            // 2026-08-23: real feedback, live - specific tool names
            // (Flutter, Claude) moved out of this sentence entirely -
            // "these can be listed in the Credits" - so this line
            // stays generic ("using tools") and doesn't duplicate what
            // Credits already states. Flutter added to Credits below,
            // Claude was already there.
            Text(
              'Built by kworld with real programming skill, using '
              'tools - AI is a coding tool here, the same as any '
              'compiler or IDE. Thanks to public education and the '
              'global community that made these skills possible.',
              style: TextStyle(color: kTextMid, fontSize: 14, height: 1.6),
            ),
            // 2026-08-23: reordered alphabetically (CONTACT, CREDITS,
            // DISCLAIMER, SETUP GUIDE, SUPPORT) - real feedback, live,
            // "Alphabetise About." "Open-source licenses" stays right
            // after CREDITS, unlabeled - thematically paired with it
            // (dependency credits + their licenses), not its own
            // alphabetized heading.
            const SizedBox(height: 20),
            Text('CONTACT',
                style: TextStyle(
                    color: kTextDim,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5)),
            const SizedBox(height: 6),
            Text(
              '$kNoteAppName support and FOSS collaboration welcome - '
              'open an issue at codeberg.org/kworld/localsync',
              style: TextStyle(color: kTextMid, fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 20),
            Text('CREDITS',
                style: TextStyle(
                    color: kTextDim,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5)),
            const SizedBox(height: 6),
            // 2026-08-23: real feedback, live - "reword to public
            // library CHUV, public library Palais de Rumine, public
            // library Médiathèque Valais Sion Makerspace" - noun-first
            // (matches the house naming rule), and re-clusters all
            // three under "P" instead of being scattered across C/M/P.
            Text(
              'Bash, Blender, C, C++, Claude, Codemagic, Dart, Eye of '
              'MATE, Flameshot, Flutter, GIMP, iLoader, Inkscape, '
              'iPhone, Kanban plugin, Logseq, Obsidian, Public library '
              'CHUV, Public library Médiathèque Valais Sion Makerspace '
              '(3D printing), Public library Palais de Rumine, '
              'Raspberry Pi, Terminal, Text Editor, Transport Lausanne, '
              'Vim',
              style: TextStyle(color: kTextMid, fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 12),
            TextButton(
              style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  alignment: Alignment.centerLeft),
              onPressed: () => showLicensePage(
                context: context,
                applicationName: 'LocalSync',
                applicationVersion: kAppVersion,
              ),
              child: Text('Open-source licenses',
                  style: TextStyle(color: kGreen, fontSize: 13)),
            ),
            const SizedBox(height: 20),
            Text('DISCLAIMER',
                style: TextStyle(
                    color: kTextDim,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5)),
            const SizedBox(height: 6),
            Text(
              'LocalSync syncs your $kContainerName over your own network - '
              'nothing is stored on any server this app controls. This '
              'app is provided as-is, with no guarantee against data loss.',
              style: TextStyle(color: kTextMid, fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 10),
            // 2026-08-23: real feedback, live - the previous single
            // run-on sentence was vague on what "keep your own backups"
            // actually means. Real points now, exact wording given,
            // each tied back to what LocalSync/the user's own setup
            // actually looks like rather than generic advice. Broader
            // cybersecurity education (passwords, social media, data
            // storage) stays out of this app - that belongs on the
            // separate Website knowledge-base product, not here.
            Text('Best practice 3-2-1:',
                style: TextStyle(
                    color: kTextMid,
                    fontSize: 13,
                    height: 1.6,
                    fontWeight: FontWeight.w700)),
            Text('3 copies of anything that matters',
                style: TextStyle(color: kTextMid, fontSize: 13, height: 1.6)),
            Text('2 different types of storage (like phone-LocalSync-desktop)',
                style: TextStyle(color: kTextMid, fontSize: 13, height: 1.6)),
            Text('1 copy kept off-site (SSD USB enclosure FTW)',
                style: TextStyle(color: kTextMid, fontSize: 13, height: 1.6)),
            const SizedBox(height: 20),
            // 2026-08-21: real feedback, live - "where is the manual
            // on the app? I don't see it" (asked twice) - the desktop
            // setup guide (docs/desktop-setup.md) only ever lived in
            // the repo, nothing in the app pointed to it. Same plain-
            // text-URL pattern as CONTACT above, not a new in-app
            // markdown renderer - that's real scope (mermaid support,
            // asset bundling) this doesn't need yet.
            Text('SETUP GUIDE',
                style: TextStyle(
                    color: kTextDim,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5)),
            const SizedBox(height: 6),
            Text(
              'Desktop-side setup (git, SSH, the bare repo) - '
              'codeberg.org/kworld/localsync/src/branch/main/docs/desktop-setup.md',
              style: TextStyle(color: kTextMid, fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 20),
            // 2026-08-23: real feature request, live - "donation link
            // yes." Bitcoin Lightning donation only, not tied to any
            // paid feature or unlock - sidesteps App Store IAP review
            // entirely since nothing in the app is gated by this.
            // Real address applied 2026-08-23 (was a placeholder
            // before that).
            Text('SUPPORT',
                style: TextStyle(
                    color: kTextDim,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5)),
            const SizedBox(height: 6),
            Text(
              'If LocalSync saves you money or hassle, Bitcoin Lightning '
              'donations are welcome - entirely optional, unlocks nothing.',
              style: TextStyle(color: kTextMid, fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: () {
                Clipboard.setData(const ClipboardData(
                    text: 'steamyice42@walletofsatoshi.com'));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Lightning address copied')),
                );
              },
              child: Text('steamyice42@walletofsatoshi.com',
                  style: TextStyle(color: kGreen, fontSize: 13)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Close',
              style: TextStyle(color: kGreen, fontSize: 15)),
        ),
      ],
    ),
  );
}

// 2026-08-21: _AutoBadge removed - see the ConstrainedBox comment above
// in _AppBarRepoStatus for why (real app-bar overflow bug, user's own
// fix: drop the redundant badge instead of chasing more spacing).

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

    if (hasSyncing) {
      return const Icon(Icons.sync, color: Colors.amber, size: 22);
    }
    if (hasError) {
      return const Icon(Icons.error_outline, color: Colors.redAccent, size: 22);
    }
    if (allOk) {
      // 2026-08-23: real feature request, live - "make the circle a
      // shield hinting at encryption and or cybersecurity." Was
      // Icons.check_circle_outline (a plain circle+tick) - Material's
      // built-in verified_user glyph is already a shield with a
      // checkmark inside, so this keeps the "all good" meaning while
      // reading as a security badge, not a custom SVG (this app's
      // established preference - see settings_screen.dart's own note
      // on the same tradeoff).
      return Icon(Icons.verified_user, color: kGreen, size: 22);
    }
    return Icon(Icons.circle_outlined, color: kTextDim, size: 22);
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
// row 1, right of LOCALSYNC and left of the kebab icon and green
// tick?" - the repo tile's summary moved into the app bar itself, and
// the separate ListView row it used to live in is gone (see the body
// builder below). Tap still triggers a pull, same as the row did.
//
// 2026-08-20: "Multi repo needed on app... row 1 with a drop down for
// repository 1 or 2 or more switcher" - gained a small dropdown next
// to the status, but only once a second sync connection actually
// exists (allRepos.length > 1) - single-vault use, the common case,
// looks exactly as it did before this.
class _AppBarRepoStatus extends StatelessWidget {
  final Repository repo;
  final List<Repository> allRepos;
  final VoidCallback onTap;
  final ValueChanged<int> onSelect;
  const _AppBarRepoStatus({
    required this.repo,
    required this.allRepos,
    required this.onTap,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final isSyncing = repo.status == SyncStatus.syncing;
    // Fixed 2026-08-09, relocated here 2026-08-17: full error text
    // (diagnosis + resolution + raw exception) was getting truncated
    // to one line with no way to see the rest - tapping while an
    // error is active shows the full dialog instead of triggering
    // another pull, which would just fail again the same way.
    final hasError = repo.status == SyncStatus.error && repo.lastError != null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            if (hasError) {
              _showFullError(context, repo);
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
                    // 2026-08-20: real bug, live - "kebab icon is now
                    // overrun by the AUTO text," a real vault's longer
                    // name (e.g. "Obsidian_phone_vault") pushed the
                    // AUTO badge and kebab icon out of the app bar
                    // entirely. Only ever surfaced with a long name -
                    // every test vault used so far had a short
                    // timestamp-style name, so this never showed. The
                    // Flexible+ellipsis here relies on a bounded max-
                    // width reaching it through Center/Column/Padding
                    // above, which apparently isn't reliably happening -
                    // an explicit ConstrainedBox guarantees it can never
                    // push its siblings regardless of that ancestor
                    // chain's behavior.
                    // 2026-08-21: real feedback, live, two rounds of
                    // spacing fixes that didn't hold - "the drop down
                    // arrow is exactly behind the kebab icon" persisted
                    // even after forcing a real gap on the actions
                    // side. Same root class of bug as the 2026-08-20
                    // "AUTO text overran the kebab" fix above: Center
                    // doesn't clip an overflowing child, so if this
                    // Row's total natural width (dot + name + AUTO
                    // badge + dropdown) exceeds the space actually
                    // available, the surplus paints straight through
                    // whatever's next to it instead of being contained.
                    // User's own proposed fix: drop the AUTO badge
                    // entirely - the same information already exists
                    // one tap away in the kebab menu's "Pull manually"
                    // (currently AUTO) / "Pull automatically" (currently
                    // MANUAL) wording, so nothing is actually lost, and
                    // removing ~45px of content is a real, direct fix
                    // for the overflow class of bug, not another
                    // spacing patch on top of it.
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 110),
                      child: Text(
                        repo.name,
                        style: TextStyle(
                            color: kStar,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
                if (hasError)
                  Text(
                    // lastError is just the diagnosis now (see the
                    // 2026-08-20 note on this field in models/
                    // repository.dart) - no longer a joined multi-line
                    // blob needing a manual split to get one line.
                    repo.lastError!,
                    style:
                        const TextStyle(color: Colors.redAccent, fontSize: 10),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                else if (isSyncing)
                  Text(repo.syncPhase.label,
                      style: TextStyle(color: kTextMid, fontSize: 10))
                else if (repo.lastSync != null)
                  Text('synced ${_timeAgo(repo.lastSync!)}',
                      style: TextStyle(color: kTextMid, fontSize: 10)),
              ],
            ),
          ),
        ),
        // 2026-08-21: real root cause of the "multi-repo display bug"
        // open since 2026-08-20, found live - this WAS always building
        // correctly (allRepos.length > 1 genuinely fired, the repo
        // really was saved) - the actual problem was purely a tap-
        // target one. padding: EdgeInsets.zero shrank this button's
        // hit area down to just its 20px icon, sitting immediately
        // next to the AppBar's kebab PopupMenuButton (default padding,
        // a much bigger hit area) with zero gap between them - taps
        // aimed at the visible arrow were landing on the kebab instead.
        // Not a data/state bug at all, once actually seen on-device.
        if (allRepos.length > 1) ...[
          PopupMenuButton<int>(
            color: kSurface,
            tooltip: 'Switch $kContainerName',
            icon: Icon(Icons.arrow_drop_down, color: kTextMid, size: 20),
            onSelected: onSelect,
            itemBuilder: (_) => [
              for (final r in allRepos)
                PopupMenuItem(
                  value: r.id,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        r.id == repo.id ? Icons.check : null,
                        color: kGreen,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      _StatusDot(status: r.status),
                      const SizedBox(width: 8),
                      Text(r.name,
                          style: TextStyle(color: kStar, fontSize: 14)),
                    ],
                  ),
                ),
            ],
          ),
          // 2026-08-21: real gap from the fix above - the button's own
          // hit area now covers the icon plus padding, but nothing
          // separated that hit area from the AppBar's kebab actions
          // button sitting immediately to its right. This reserves a
          // real visual and tap gap between the two.
          const SizedBox(width: 8),
        ],
      ],
    );
  }
}

