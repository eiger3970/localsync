// screens/home_screen.dart

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../constants.dart';
import '../models/repository.dart';
import '../services/device_name.dart';
import '../services/purchase_service.dart';
import '../services/repository_provider.dart';
import '../services/sync_service.dart';
import '../features/linking/linking_state.dart' show LinkingError;
import '../widgets/controllable_gif.dart';
import '../widgets/diag_card.dart';
import '../widgets/floating_hearts.dart';
import '../widgets/flowing_data_animation.dart';
import '../widgets/free_tier_banner_ad.dart';
import '../widgets/gif_swipe_trigger.dart';
import '../widgets/help_wizard.dart';
import '../widgets/pkm_sync_upsell.dart';
import '../widgets/sync_confirm_dialog.dart';
import 'commit_screen.dart';
import 'conflicts_screen.dart';
import 'linking_screen.dart';
import 'welcome_hero_screen.dart';
import '../features/linking/linking_controller.dart';
import 'pairing_screen.dart';
import 'reminders_screen.dart';
import 'security_info_screen.dart';
import 'settings_screen.dart';
import '../services/sound_service.dart';

// 2026-09-18: real bug, found after the SceneDelegate fix still left
// "DEBUG PULL: anim=true playing=false" but no visible animation - a
// classic GlobalKey mistake. These used to be created fresh inside
// HomeScreen's own build() method every single rebuild - a brand-new
// GlobalKey object at the same tree position makes Flutter discard the
// old element and create a new one, which silently kills whatever
// animation had just started (via triggerConfirm()) before it ever
// paints a frame. Cold launch is full of rebuilds happening moments
// apart (repos loading, theme loading, etc.) - exactly when a widget-
// tap/Quick Action fires this. A real swipe never hit this because it
// only ever happens once the app's already settled, long after that
// initial churn. Module-level, created once for the app's lifetime -
// only one sync gesture zone is ever visible at a time, so a single
// persistent pair is correct for this app's actual usage.
final _pullKey = GlobalKey<GifSwipeTriggerState>();
final _pushKey = GlobalKey<GifSwipeTriggerState>();
// 2026-09-18 (round 5): real regression, live - "gif and graphics show
// for a second, black screen..., then gif and graphics show again,
// then app crashes." Clearing pendingQuickAction synchronously (the
// round-4 fix, right below) stopped this block from double-scheduling
// itself, but it also cleared the flag BEFORE the real action actually
// ran - AutoSyncOnResume's own guard (`if (pendingQuickAction != null)
// return`) checks that exact same flag to know "something else is
// already syncing, skip my own auto-sync." Clearing it early meant that
// guard could see it as already-clear and fire its OWN independent
// push/pull concurrently with the widget-triggered one - the same
// concurrent-git-access crash class, reintroduced by the fix meant to
// prevent it. This flag does the actual job the early clear was for
// (stop re-scheduling) without touching when pendingQuickAction itself
// gets cleared - that goes back to happening only once the deferred
// action truly runs, so AutoSyncOnResume keeps seeing it correctly for
// the whole window it needs to.
bool _quickActionScheduled = false;

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
        //
        // 2026-08-30: real root cause found, after 4 rounds of padding/
        // tap-target tweaks that never actually fixed it - centerTitle
        // was never set, so it sat on Flutter's platform default, which
        // is TRUE on iOS. That triggers a DIFFERENT layout algorithm
        // than this manual Expanded+Center: iOS centered-title mode
        // squeezes the title's available width down to roughly
        // `toolbarWidth - 2*max(leadingWidth, actionsWidth)`, far
        // narrower than the real leftover space - that's what caused
        // the early wrap (row 1 had real room the box didn't reflect)
        // and the dead space before the kebab, regardless of any local
        // padding tweak. Explicit false lets this screen's own manual
        // centering use the real leftover space instead of competing
        // with iOS's symmetric-centering math.
        centerTitle: false,
        // 2026-08-30: real cause of the LAST 46dp of gap, found via a
        // Key-tagged measurement, not another guess - even with
        // centerTitle:false, AppBar reserves its own default 16dp
        // titleSpacing on both sides of the title (NavigationToolbar.
        // kMiddleSpacing), on top of everything this screen already
        // manages manually (the logo, the explicit SizedBox(24) in
        // actions). Zero removes that invisible double-reservation.
        titleSpacing: 0,
        // 2026-08-30, corrected - "object 2 [name] isn't spread right of
        // object 1 [logo] and left of object 3 [kebab]." The name needs
        // to actually SPAN the space between the logo and the kebab, not
        // sit at its own small natural width - Expanded does that, using
        // the real leftover width (freed up by centerTitle:false and
        // titleSpacing:0 above), no fixed cap to get wrong again.
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
              key: const ValueKey('titleExpanded'),
              child: Consumer<RepositoryProvider>(
                builder: (_, provider, __) => provider.repos.isEmpty
                    ? const SizedBox.shrink()
                    : _AppBarRepoStatus(
                        repo: provider.selectedRepo!,
                        allRepos: provider.repos,
                        onTap: () => _runAndShow(
                            context,
                            ({bool confirmed = false}) => provider
                                .pullRepository(provider.selectedRepo!.id!,
                                    confirmed: confirmed),
                            repo: provider.selectedRepo),
                        onSelect: provider.selectRepo,
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
          // 2026-08-28: real feedback, live - "kebab icon is too far
          // left, leaving too much space to its right [before Help] and
          // taking away valuable real estate on its left [from the repo
          // name/dropdown]." Widened from 14 to give the name area more
          // room, and the kebab+Help pairing below gets tight explicit
          // padding instead of each IconButton's default ~48px tap
          // target stacking into a much bigger visual gap than intended
          // between them - net effect shifts the kebab right, closer to
          // Help, exactly as asked.
          //
          // 2026-08-30: that 24dp was compensating for the name box
          // being starved of real width by the titleSpacing/reserved-
          // constant bugs fixed today - the name area no longer needs
          // this widened purely to "make room." Measured preview still
          // showed a visible gap at 24dp, so shrinking to a minimal
          // real separator now that the underlying bug is actually
          // fixed, not compensated around.
          //
          // 2026-08-30: real feedback, live - "move kebab icon right."
          // Zero - the dot+text before it already carries enough visual
          // separation on its own (padding + the name box's own edge).
          const SizedBox(width: 0),
          // 2026-08-29: real feedback, live - "kebab icon is still too
          // far left from the help icon" even after the padding tweak
          // above. PopupMenuButton's icon builds an internal IconButton
          // that enforces Material's default 48x48 minimum tap target
          // regardless of the explicit `padding` value - that invisible
          // extra footprint, not the padding itself, is what was still
          // pushing Help further away than it looked like it should.
          // shrinkWrap removes that enforced minimum so the button's
          // real size actually reflects its icon + padding.
          Theme(
            data: Theme.of(context).copyWith(
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: Consumer<RepositoryProvider>(
              builder: (_, provider, __) => PopupMenuButton<String>(
                color: kSurface,
                // 2026-08-30: real device feedback asked for kebab-to-
                // Help spacing to match Help-to-edge spacing. First
                // attempt measured PopupMenuButton's own semantic touch-
                // target box (9dp vs 15dp, looked unbalanced) and widened
                // padding to compensate - wrong measurement target: the
                // VISIBLE glyph-to-glyph gap (what the eye actually
                // judges "balance" by) was already 15dp vs 15dp, exactly
                // matched, before that change. The touch target is
                // deliberately asymmetric (larger tap area, same visual
                // position) - reverted back to the original padding,
                // then measured the real remaining gap (18dp vs Help's
                // 15dp) and closed just that small real difference.
                padding: const EdgeInsets.only(left: 0, right: 6),
                icon: Icon(Icons.more_vert, color: kGreen, size: 22),
                onSelected: (v) {
                  if (v == 'pair') _openPairing(context);
                  if (v == 'link') _openLinking(context);
                  if (v == 'about') {
                    // 2026-09-18: real ask, live - "Support floating
                    // hearts decrease per higher tiers." The only real,
                    // currently-wired signal for this is repo.syncMode -
                    // an Obsidian-vault repo can't exist without already
                    // having gone through the Tier 1 unlock flow
                    // (PkmSyncUpsell's onUnlocked), while Tier 2/3/4
                    // aren't gated by a real purchase yet (still
                    // "ungated during testing," per docs/product-
                    // tiers.md) - so paid-vs-free is the real
                    // granularity available today, not a finer ladder.
                    _showAbout(context,
                        paidTier: provider.selectedRepo?.syncMode ==
                            SyncMode.obsidianVault);
                  }
                  if (v == 'device_name') _editDeviceName(context, provider);
                  if (v == 'settings') {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SettingsScreen()));
                  }
                  if (v == 'reminders') {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const RemindersScreen()));
                  }
                  if (v == 'security') {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SecurityInfoScreen()));
                  }
                  final repo = provider.selectedRepo;
                  if (repo == null) return;
                  if (v == 'commit') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => CommitScreen(repo: repo)),
                    );
                  }
                  if (v == 'toggle_auto') provider.toggleAutoSync(repo.id!);
                  if (v == 'sync_desktop_now') {
                    _triggerDesktopSyncNow(context, provider, repo.id!);
                  }
                  if (v == 'conflicts') {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ConflictsScreen(repo: repo)))
                        .then((_) => provider.refreshConflicts(repo.id!));
                  }
                  if (v == 'delete') _confirmDelete(context, provider, repo);
                },
                // 2026-08-18: full menu cleanup per explicit list - one
                // flat alphabetical order (About, Conflicts, Connection,
                // Device name, Pair, Pull, Vault), no dividers. Commit
                // and Desktop sync both stay pinned out of alphabetical
                // order, not arbitrarily - stated reasons below.
                // One-line explainer under each label still stands in
                // for a hover tooltip, which doesn't fire on iOS tap.
                //
                // 2026-09-18: real ask, live - "Move desktop sync to
                // top and commit with message underneath." Swapped -
                // Desktop sync now pinned first, Commit second.
                itemBuilder: (_) {
                  final hasRepo = provider.repos.isNotEmpty;
                  return [
                    // 2026-09-17: real ask, live - "this is an important
                    // button." Moved out of alphabetical order (was
                    // between Settings and Vault) and pinned first as of
                    // 2026-09-18, per direct instruction above. Renamed
                    // Sync desktop now -> Desktop sync (Sentence case,
                    // nouns first - matches Desktop username/Desktop
                    // vault path's naming in Settings).
                    if (hasRepo)
                      const PopupMenuItem(
                        value: 'sync_desktop_now',
                        // 2026-09-17: real ask, live - "add a slight
                        // line space under Desktop sync," then "need a
                        // space between Desktop sync and About" - first
                        // pass (6px) wasn't visible enough. Padding on
                        // this one item's own content, not a divider
                        // (this menu deliberately has none) and not a
                        // change to any other row's spacing.
                        //
                        // 2026-09-18: this item moved from second to
                        // first (see itemBuilder's own comment above) -
                        // the bottom padding still reads correctly since
                        // whatever comes right after it (Commit, now)
                        // still benefits from the same breathing room.
                        child: Padding(
                          padding: EdgeInsets.only(bottom: 18),
                          child: _MenuRow(
                            icon: Icons.bolt_outlined,
                            label: 'Desktop sync',
                            // 2026-09-17: reworded to the user's own
                            // exact wording, used verbatim.
                            subtitle:
                                'Runs desktop immediately, rather than '
                                'waiting',
                          ),
                        ),
                      ),
                    // 2026-09-18: real ask, live (round 2) - "About to
                    // be above Commit with message... alphabetical."
                    // Restored to before Commit - as a bonus, About,
                    // Commit and Conflicts now read in genuine
                    // alphabetical order (A < Comm < Conf) without
                    // Commit needing to be a special-cased deviation for
                    // this stretch of the list at all.
                    const PopupMenuItem(
                      value: 'about',
                      child: _MenuRow(icon: Icons.info_outline, label: 'About'),
                    ),
                    // Commit stays pinned near the top since it's what
                    // gets tapped most once set up is done - a stated
                    // reason to deviate from alphabetical, not an
                    // arbitrary one (see house naming rule).
                    if (hasRepo)
                      const PopupMenuItem(
                        value: 'commit',
                        child: _MenuRow(
                          icon: Icons.edit_note,
                          label: 'Commit with message...',
                        ),
                      ),
                    if (hasRepo)
                      PopupMenuItem(
                        value: 'conflicts',
                        // 2026-09-18: real correction, live - "I didn't
                        // say make the kebab icon amber, I said make
                        // the Conflicts icon amber." Moved off the ⋮
                        // trigger itself (reverted above) onto this
                        // row's own icon, where the signal is actually
                        // about the specific menu item it names.
                        child: _MenuRow(
                          icon: Icons.compare_arrows,
                          iconColor: provider.selectedRepo != null &&
                                  provider.hasConflicts(
                                      provider.selectedRepo!.id!)
                              ? Colors.amber
                              : null,
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
                          // 2026-08-30: real device feedback - "why anti
                          // clockwise, is clockwise possible?" Mirrored
                          // (see _MenuRow's own comment on flipIcon for
                          // why a mirror, not a rotation, is what
                          // actually reverses it) - genuinely unverified
                          // which direction either version reads as on a
                          // real device, Material icon glyphs don't
                          // render in this repo's headless test setup.
                          flipIcon: true,
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
                    // 2026-09-18: real ask, live - "name is Reminders, so
                    // it sits in the Kebab icon menu between Pull
                    // manually and Security." Controls the same
                    // amber/red day thresholds LocalSyncWidget.swift's
                    // traffic-light dot already used - see
                    // reminders_screen.dart's own header for the full
                    // history. Round 2: renamed label ("Reminders are a
                    // backup reminder one could say") and "colors" ->
                    // "colours".
                    if (hasRepo)
                      const PopupMenuItem(
                        value: 'reminders',
                        child: _MenuRow(
                          icon: Icons.notifications_outlined,
                          label: 'Reminder backup',
                          subtitle: 'Widget colours & sync notifications',
                        ),
                      ),
                    // 2026-08-27: moved here from a standalone AppBar icon -
                    // "keep help on the title bar... security icon can move
                    // to the kebab menu" (real feedback, live). Alphabetical
                    // slot between Pull and Settings, same as everything
                    // else in this menu. Reuses _StatusIcon's own
                    // icon/color logic (still a real shield glyph, colored
                    // by sync/error state) rather than a fixed icon -
                    // that live-status meaning is exactly what's being
                    // traded for Help's bar slot, so it's worth keeping
                    // inside the menu even though it's no longer glanceable
                    // without opening it.
                    if (hasRepo)
                      PopupMenuItem(
                        value: 'security',
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // 2026-09-09: real feedback, live - "keep
                            // the link to open How your data is
                            // protected, but the image tapped shows
                            // what the status means, just a few short
                            // text words." A nested GestureDetector
                            // wins the gesture arena over the
                            // PopupMenuItem's own tap (same pattern as
                            // an IconButton inside a ListTile) - tapping
                            // the icon shows the status as a SnackBar
                            // and stops there (PopupMenuItem.onTap
                            // never fires, menu stays open), tapping
                            // anywhere else in the row still closes the
                            // menu and opens the full explanation
                            // screen exactly as before.
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                content: Text(
                                    _securityStatusLabel(provider.repos)),
                                duration: const Duration(seconds: 2),
                              )),
                              child: _StatusIcon(repos: provider.repos),
                            ),
                            const SizedBox(width: 12),
                            Text('Security',
                                style: TextStyle(color: kStar, fontSize: 14)),
                          ],
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
                        // 2026-09-03: real feedback, live - reverses the
                        // alphabetical order above (deliberate new
                        // preference, not a bug) - matches the Settings
                        // screen's own field order swap and rename.
                        //
                        // 2026-09-09: real feedback, live - field names
                        // drifted from Settings' own current labels
                        // (that screen now says "Desktop sync folder"
                        // and has since grown a real 4th field,
                        // "Desktop vault path") - and listing every
                        // field name here was "too much info in the
                        // Kebab icon." First terse rewrite dropped IP
                        // address entirely - real pushback, live:
                        // "where's the fucking IP address?" One compact
                        // line naming all three real fields instead.
                        subtitle: 'IP, sync folder & vault path',
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
          ),
          // 2026-08-27: the security status shield used to live here -
          // moved into the kebab menu (see 'security' PopupMenuItem
          // above) per explicit direction: "keep help on the title
          // bar... the help is more important." This is its replacement,
          // opening the new branching help wizard (help_wizard.dart)
          // instead of a single static dialog.
          IconButton(
            icon: Icon(Icons.help_outline, color: kGreen),
            tooltip: 'Help',
            padding: const EdgeInsets.only(left: 0, right: 12),
            constraints: const BoxConstraints(),
            onPressed: () => showHelpWizard(context, 'A'),
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
          // that?" - a PREVIOUS page 1 was removed because it and
          // LinkingScreen's own _IdleView were both a drag-to-connect
          // gesture, back to back - page 1's drag did nothing except
          // open page 2, which then made the user drag again before
          // anything real happened. That's not what SyncChoiceScreen is
          // (2026-08-27) - it's two plain taps, no gesture duplicated,
          // and it decides something real (which flow the drag gesture
          // on the next screen leads to) instead of being a no-op
          // stepping stone. Real feedback that prompted it: "a normie
          // needs the hand held from install of app... PKM terminology
          // is too much" - the very first thing a fresh install used to
          // show was "PKM VAULT SETUP" with vault-lock imagery, before a
          // Tier 0 (plain file sync) user ever saw anything relevant to
          // them. pushReplacement, not push - backing out of setup with
          // zero repos configured should land on an actual empty state,
          // not instantly redirect right back into setup again.
          if (provider.repos.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) {
                Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const WelcomeHeroScreen()));
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
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ConflictsScreen(repo: pendingRepo)))
                    .then((_) => provider.refreshConflicts(pendingRepo.id!));
              }
            });
          }
          // 2026-09-18: real gap found, live - "Errors when syncing
          // under the top title bar are too small to read, can you
          // move to the bottom snack bar to make larger." Same pending-
          // flag-for-the-next-frame pattern as pendingConflictRepoId
          // above - the auto-launch pull (RepositoryProvider._init())
          // has no BuildContext of its own to show a SnackBar from.
          final pendingFailure = provider.pendingAutoSyncFailure;
          if (pendingFailure != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              provider.clearPendingAutoSyncFailure();
              if (!context.mounted) return;
              // 2026-09-18: real feedback, live - "Pushed as desktop
              // home screen message stays for a long time... I then
              // tap Desktop sync and have to wait for the Pushed
              // message to disappear." ScaffoldMessenger queues
              // SnackBars by default - a new one waits for whatever's
              // already showing to run out its FULL duration first,
              // not just its exit animation. hideCurrentSnackBar()
              // dismisses the old one immediately so this one doesn't
              // wait behind it.
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: kSurface,
                  content: Center(
                    child: Text(syncResultMessage(pendingFailure),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: kStar, fontSize: 16)),
                  ),
                  duration: const Duration(seconds: 12),
                ),
              );
            });
          }
          // 2026-09-16: same pattern as pendingConflictRepoId just above -
          // main.dart's QuickActions().initialize callback sets this
          // (real Home Screen "Pull"/"Push" long-press actions) with no
          // BuildContext of its own to act on. Runs through the exact
          // same _runAndShow the swipe gesture below uses - same confirm
          // dialogs, same SnackBar feedback, same cannotFastForward
          // auto-recovery on push. Cleared immediately, same one-shot
          // reasoning as the conflict case.
          //
          // 2026-08-20: acts on the selected repo (see app-bar
          // dropdown), not always the first one, now that multiple can
          // genuinely exist.
          Future<void> onPull() => _runAndShow(
              context,
              ({bool confirmed = false}) =>
                  provider.pullRepository(repo.id!, confirmed: confirmed),
              repo: repo);
          // 2026-09-15: real feedback, live - "when a user with no
          // claudeai has this error, will it be fixed by the app?"
          // Fixed for the Conflicts screen's own PUSH button
          // (conflicts_screen.dart's _runPushWithAutoRecovery) but this
          // everyday swipe gesture is the actual common path most users
          // hit cannotFastForward through - fixing one and not the
          // other would leave the far more frequent case still showing
          // a bare error with no self-recovery. pullFallback wires the
          // exact same auto-pull-then-retry into _runAndShow itself.
          Future<void> onPush() => _runAndShow(
              context,
              ({bool confirmed = false}) =>
                  provider.pushRepository(repo.id!, confirmed: confirmed),
              repo: repo,
              pullFallback: ({bool confirmed = false}) =>
                  provider.pullRepository(repo.id!, confirmed: confirmed));
          // 2026-09-16: same pattern as pendingConflictRepoId just above -
          // main.dart's QuickActions().initialize callback sets this
          // (real Home Screen "Pull"/"Push" long-press actions) with no
          // BuildContext of its own to act on. Cleared immediately, same
          // one-shot reasoning as the conflict case.
          //
          // 2026-09-18: real ask, live - "Widget pull and push opened
          // home screen but gifs weren't moving?" This used to call
          // _runAndShow directly - a real sync, but the gif/flow
          // animation (owned by GifSwipeTrigger's own onConfirm wrapper
          // below) never played, since nothing here ever asked it to.
          // Now runs through pullKey/pushKey's triggerConfirm() first -
          // same onPull/onPush closures underneath either way, with a
          // direct onPull()/onPush() fallback if .currentState is
          // somehow still null.
          //
          // 2026-09-18 (round 4): real crash, live - "app crashed back
          // to widget" on cold launch specifically. Real cause: this
          // whole block re-runs on EVERY rebuild while
          // provider.pendingQuickAction is still non-null - cold launch
          // is full of rebuilds happening moments apart (repos loading,
          // theme loading, etc.), each one registering its OWN callback
          // before the first one had a chance to fire, so the SAME
          // single tap could fire triggerConfirm()/onPull()/onPush()
          // more than once, concurrently - the exact same class of bug
          // ("I ran push and the app closed", concurrent git2dart FFI
          // access) already fixed once for the real swipe gesture,
          // reintroduced here.
          //
          // 2026-09-18 (round 5): _quickActionScheduled (declared at
          // file scope above) is what actually stops the re-scheduling
          // now, not an early clear of pendingQuickAction itself - see
          // that field's own comment for why clearing early caused a
          // different concurrent-sync regression via AutoSyncOnResume.
          final pendingQuickAction = provider.pendingQuickAction;
          if (pendingQuickAction != null && !_quickActionScheduled) {
            _quickActionScheduled = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _quickActionScheduled = false;
              provider.clearPendingQuickAction();
              if (!context.mounted) return;
              if (pendingQuickAction == 'action_pull') {
                final state = _pullKey.currentState;
                if (state != null) {
                  state.triggerConfirm();
                } else {
                  onPull();
                }
              } else if (pendingQuickAction == 'action_push') {
                final state = _pushKey.currentState;
                if (state != null) {
                  state.triggerConfirm();
                } else {
                  onPush();
                }
              }
            });
          }
          // 2026-08-17: the repo tile's summary row moved into the app
          // bar (_AppBarRepoStatus above) - nothing left to show here
          // except the gesture zone, which now gets the full body.
          final gestureZone = _SyncGestureZone(
            pullKey: _pullKey,
            pushKey: _pushKey,
            // 2026-09-18: real ask, live - "middle between Pull and
            // Push is blank, perfect for ad space... add 2nd gap."
            // Tier 0 (free/genericFolder) only, same paid-tier-stays-
            // ad-free split as the top banner - this widget is shared
            // by both tiers (see the syncMode branch below), so the
            // gate has to live here, at construction, not inside
            // _SyncGestureZone itself.
            showMidAd: repo.syncMode == SyncMode.genericFolder,
            onPull: onPull,
            onPush: onPush,
          );
          // 2026-08-27: real feedback, live - "the free app can then
          // setup obsidian with the special recipe algorithm... running
          // through the obsidian install once an IAP is paid." Only a
          // Tier 0 (genericFolder) repo gets this - an existing Obsidian
          // vault repo's home screen is completely unchanged, still just
          // the gesture zone with the full body.
          if (repo.syncMode != SyncMode.genericFolder) return gestureZone;
          return Column(
            children: [
              // 2026-09-17: real ask, live - "Ads location? Top of home
              // screen under top bar?" Moved up from the bottom of this
              // Column (below the gesture zone) to right under the app
              // bar - higher-visibility slot, and doesn't compete with
              // the PUSH/PULL gesture zones for attention the way a
              // bottom placement did.
              const SafeArea(bottom: false, child: FreeTierBannerAd()),
              Padding(
                padding: const EdgeInsets.all(12),
                child: PkmSyncUpsell(
                  purchases: context.watch<PurchaseService>(),
                  onUnlocked: () {
                    // 2026-08-28: reset() before navigating in, same fix
                    // _openLinking already needed for the exact same
                    // singleton-controller staleness bug ("Add another
                    // vault used to land straight on a stale failure
                    // screen from whatever the PREVIOUS linking attempt
                    // left behind") - this call site was missing it.
                    // Matters more now that LinkingScreen's own initState
                    // (_skipStage1IfAlreadyPaired) calls startLinking()
                    // immediately on mount rather than waiting for a user
                    // gesture, so a stale non-idle/non-failed _step here
                    // would trip straight into that method's assert.
                    final ctrl = context.read<LinkingController>();
                    ctrl.reset();
                    ctrl.preferredMode = SyncMode.obsidianVault;
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const LinkingScreen()));
                  },
                ),
              ),
              Expanded(child: gestureZone),
            ],
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
  //
  // 2026-09-22: real bug, live - "Vault -> new -> ... shows PKM VAULT
  // SETUP, wrong page for a free user." This navigated straight to
  // LinkingScreen without ever setting preferredMode or offering a
  // choice - WelcomeHeroScreen (first-launch only, until now) is the
  // ONLY place that ever lets the user pick free vs Obsidian before
  // proceeding, so a returning user adding a SECOND repo had no way to
  // reach the free/genericFolder setup at all - LinkingScreen's own
  // title ternary (line ~223) defaults to the Obsidian/PKM framing
  // whenever preferredMode isn't genericFolder, which it never could be
  // from this entry point. Routes through WelcomeHeroScreen now instead
  // - same mode-choice + preview flow first launch already uses, not a
  // new screen - reset() still happens first exactly as before.
  void _openLinking(BuildContext context) {
    context.read<LinkingController>().reset();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const WelcomeHeroScreen()),
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
            style: TextStyle(color: kStar, fontSize: 16)),
        content: Text(
          // 2026-08-28: was always "$kGenericAppLabel $kContainerName"
          // ("PKM vault") regardless of the actual repo - wrong for a
          // Tier 0 generic-folder repo, which has neither. Branches on
          // the real repo's own syncMode, same field already used to
          // decide obsidianVaultPath when the repo was created.
          repo.syncMode == SyncMode.genericFolder
              ? 'This unlinks "${repo.localPath.split('/').last}" from your '
                  'desktop folder. The folder and its files stay on this '
                  'phone.'
              : 'This unlinks "${repo.localPath.split('/').last}" from your '
                  'desktop $kGenericAppLabel $kContainerName. The '
                  '$kContainerName and its files stay on this phone.',
          style: TextStyle(color: kTextMid, fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:
                Text('Cancel', style: TextStyle(color: kTextDim, fontSize: 15)),
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
        // 2026-09-17: real ask, live - "same image from main menu" -
        // the kebab menu's own "Device name" row already uses
        // Icons.smartphone (see _MenuRow usage above), reused here so
        // the dialog visually matches what was tapped to open it.
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smartphone, color: kTextDim, size: 18),
            const SizedBox(width: 8),
            Text('Device name', style: TextStyle(color: kStar, fontSize: 16)),
          ],
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: kStar),
          decoration: const InputDecoration(hintText: "e.g. Ken's phone"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.close_rounded, color: kTextDim, size: 16),
                const SizedBox(width: 4),
                Text('Cancel',
                    style: TextStyle(color: kTextDim, fontSize: 15)),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, ctrl.text.trim()),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_rounded, color: kStar, size: 16),
                const SizedBox(width: 4),
                Text('Save', style: TextStyle(color: kStar, fontSize: 15)),
              ],
            ),
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
  // 2026-08-30: real device feedback - "why are arrow anti clockwise, is
  // clockwise possible?" on Icons.sync (Pull manually/automatically).
  // Mirroring reverses the apparent rotational direction of a symmetric
  // 2-arrow loop icon (a reflection flips chirality/spin sense; a
  // rotation alone wouldn't - sync's own 180-degree rotational symmetry
  // means rotating it looks identical). Off by default, only this one
  // row opts in.
  final bool flipIcon;
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
    this.flipIcon = false,
  });

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(icon, color: iconColor ?? kStar, size: 18);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        flipIcon ? Transform.flip(flipX: true, child: iconWidget) : iconWidget,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: TextStyle(color: labelColor ?? kStar, fontSize: 14)),
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
  final bool showMidAd;
  // 2026-09-18: real ask, live - "Widget pull and push opened home
  // screen but gifs weren't moving?" Lets a caller outside a real swipe
  // gesture (pendingQuickAction below) reach each GifSwipeTrigger's own
  // triggerConfirm() instead of calling onPull/onPush directly - see
  // gif_swipe_trigger.dart's own 2026-09-18 comment for why that
  // silently skipped the animation.
  final GlobalKey<GifSwipeTriggerState>? pullKey;
  final GlobalKey<GifSwipeTriggerState>? pushKey;
  const _SyncGestureZone(
      {required this.onPull,
      required this.onPush,
      this.showMidAd = false,
      this.pullKey,
      this.pushKey});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: GifSwipeTrigger(
            key: pullKey,
            caption: 'PULL',
            swipeDown: true,
            // 2026-08-17: "a lot of black space between PULL and
            // PUSH, can the gifs be enlarged 30%?" - another 30% up
            // from last round (90 -> 117 -> 152 -> 198 -> 257 for pull;
            // 90 -> 117 -> 152 -> 198 for push, catching up).
            gifHeight: 257,
            alignTop: true,
            onConfirm: onPull,
            // 2026-09-17: real ask, live - "Push pull flow, maybe on
            // home screen when pushing or pulling?" Adds a real Flutter
            // particle animation (drifting south-west, matching the
            // direction language already used in help_wizard.dart)
            // behind the existing git_pull.gif - "removed the gifs, but
            // should be behind it" - both stay visible together.
            animationBuilder: (key, height) => FlowBehindGif(
              key: key,
              assetPath: 'assets/gifs/git_pull.gif',
              isPush: false,
              flowColor: kGreen,
              height: height,
            ),
          ),
        ),
        // 2026-09-18: real ask, live - "middle between Pull and Push
        // is blank, perfect for ad space." Second free-tier banner slot,
        // same collapses-to-nothing-on-failure behavior as the top one
        // (FreeTierBannerAd's own doc) - never reserves dead space if
        // no ad loads.
        if (showMidAd) const FreeTierBannerAd(),
        Expanded(
          child: GifSwipeTrigger(
            key: pushKey,
            caption: 'PUSH',
            swipeDown: false,
            gifHeight: 198,
            onConfirm: onPush,
            animationBuilder: (key, height) => FlowBehindGif(
              key: key,
              assetPath: 'assets/gifs/git_push.gif',
              isPush: true,
              flowColor: kGreen,
              height: height,
            ),
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
    // 2026-09-15: real feedback, live - "sometimes the progress dot
    // changes to a progress ring. Remove the progress ring, until it's
    // 100% a clean graphic." The partial-fill CircularProgressIndicator
    // (real data during the pulling phase only, see 2026-09-09's since-
    // removed comment) looked broken/incomplete rather than clean at
    // low percentages - reverted to always showing the same rotating
    // sync icon this used everywhere else, one consistent graphic for
    // the whole syncing state instead of switching mid-sync.
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
// 2026-08-19: [repo] is optional and only used for the
// SyncOkWithConflicts case below - "way too convoluted, automate it"
// was the real complaint: a successful-looking pull gave no signal a
// conflict needed attention, so the only way to discover one was
// already knowing to check a menu with no badge on it (mapped out in
// this session's own mermaid flowchart).
// 2026-09-15: real feedback, live - "when a user with no claudeai has
// this error, will it be fixed by the app?" A plain push can never
// return SyncOkWithConflicts directly (a conflict can only come from a
// pull's merge - see sync_service.dart's _pushInIsolate, which never
// constructs one), so the note below about push's call site is still
// accurate for [op] itself - but [pullFallback] changes the picture:
// when push fails with cannotFastForward and this recovers by pulling
// instead, THAT pull genuinely can surface SyncOkWithConflicts, and it
// needs the same navigation as an ordinary pull would get. So the push
// call site now passes [repo] too, purely so this recovery path can
// still navigate correctly - a successful plain push still never hits
// that branch on its own.
//
// 2026-08-21: moved out of HomeScreen (never used `this`/instance
// state) - _showFullError's new TRY AGAIN button needs to call this
// too, and it lives in a different private class (_AppBarRepoStatus),
// which can't reach a HomeScreen instance method.
//
// 2026-09-15: [pullFallback], when given, is what turns a bare
// cannotFastForward error into a real fix instead of a dead end - the
// exact same auto-pull-then-retry conflicts_screen.dart's own PUSH
// button already does (see that file's _runPushWithAutoRecovery),
// pulled up into this shared helper so the ordinary Home screen swipe-
// to-push gesture - the actual common path most users hit this
// through, not just the post-conflict-resolution one - gets it too.
// null (every call site except the push gesture) means "no recovery,
// behave exactly as before."
// 2026-09-17: real gap found, live - see the 'sync_desktop_now' kebab
// menu item's own comment for the full story. Deliberately NOT routed
// through _runAndShow above - that function's confirmation/
// cannotFastForward-retry logic is specific to local push/pull
// semantics (a real git operation against this phone's own repo);
// this action never touches local git state at all, it just asks the
// desktop to run its own script - same SnackBar feedback, none of
// that extra machinery.
// 2026-09-17: real feedback, live - "Desktop sync, how to know when
// it's finished, need a progress indicator. Maybe flash lightning
// image yellow, then green when complete?" The kebab menu closes the
// instant the item is tapped, so there's no in-menu surface left to
// show progress on - the SnackBar itself becomes that surface: a
// pulsing yellow bolt appears the moment the tap lands (this used to
// be silent until the result came back, with nothing telling the user
// a sync was even running), replaced by the existing green-check
// result SnackBar once the real await resolves.
Future<void> _triggerDesktopSyncNow(
    BuildContext context, RepositoryProvider provider, int repoId) async {
  // 2026-09-18: real feedback, live - "Pushed as desktop home screen
  // message stays for a long time... I then tap Desktop sync and have
  // to wait for the Pushed message to disappear." A leftover SnackBar
  // from a prior push/pull (12s duration) queues this one behind it
  // otherwise - hideCurrentSnackBar() clears it immediately instead of
  // making this wait out that full duration.
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: kSurface,
      content: const _PulsingSyncStatus(label: 'Desktop syncing...'),
      duration: const Duration(seconds: 30),
    ),
  );
  final result = await provider.triggerDesktopSyncNow(repoId);
  if (!context.mounted || result == null) return;
  // 2026-09-18: real bug, caught while adding the success gif below -
  // this SnackBar showed the same green bolt + green text for BOTH a
  // real success and a real SyncFailed diagnosis, unconditionally. A
  // failure now gets its own red icon/text instead of borrowing
  // success styling.
  final isFailure = result is SyncFailed;
  if (!isFailure) {
    unawaited(SoundService.instance.play(SoundEvent.desktopSync));
  }
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: kSurface,
      content: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 2026-09-18: real ask, live - "Can you add success jumping
          // dog gif?" Reuses the same dog_success_stand.gif already
          // used for the pairing/linking success moments (see
          // ControllableGif's own doc) - one consistent mascot for
          // "this finished," not a new asset.
          if (!isFailure)
            const ControllableGif(
              assetPath: 'assets/gifs/dog_success_stand.gif',
              playing: true,
              height: 28,
              frameDurationOverrides: {4: Duration(milliseconds: 700), 5: Duration(milliseconds: 50)},
            )
          else
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
          const SizedBox(width: 10),
          // 2026-09-18: real ask, live - "Desktop sync complete text to
          // be green." Was kStar (white), matching every other sync
          // result SnackBar - success now matches its own gif, failure
          // gets its own red instead of borrowing success styling.
          Flexible(
            child: Text(syncResultMessage(result),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: isFailure ? Colors.redAccent : kGreen,
                    fontSize: 16)),
          ),
        ],
      ),
      duration: const Duration(seconds: 12),
    ),
  );
}

// Pulses opacity between dim and full while a desktop sync is running -
// yellow reads as "in progress," the completion SnackBar above switches
// to a plain kGreen bolt once the result is known.
//
// 2026-09-18: real feedback, live - "can the text also be amber and
// pulsing like the lightning bolt. Only the lightning bolt is too
// small for the human eye to watch." Was a bare _PulsingBolt icon next
// to plain static kStar text - the whole row (icon, now bigger, and
// the label) pulses together and both go amber, one shared animation
// instead of two things drawing attention separately.
class _PulsingSyncStatus extends StatefulWidget {
  final String label;
  const _PulsingSyncStatus({required this.label});

  @override
  State<_PulsingSyncStatus> createState() => _PulsingSyncStatusState();
}

class _PulsingSyncStatusState extends State<_PulsingSyncStatus>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 2026-09-18: real feedback, live - "Desktop syncing change from
    // amber to white, as long syncs look like there's a problem."
    // Amber reads as a warning/caution color, wrong signal for an
    // in-progress-but-fine operation that can legitimately take a
    // while - kStar (white) still pulses the same way, just without
    // the alarm framing.
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0).animate(_ctrl),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bolt, color: kStar, size: 28),
          const SizedBox(width: 10),
          Text(widget.label,
              style: TextStyle(
                  color: kStar, fontSize: 16, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

Future<void> _runAndShow(
  BuildContext context,
  Future<SyncResult?> Function({bool confirmed}) op, {
  Repository? repo,
  Future<SyncResult?> Function({bool confirmed})? pullFallback,
}) async {
  var result = await op();
  if (!context.mounted || result == null) return;
  if (result case SyncNeedsConfirmation()) {
    final proceed = await showSyncConfirmDialog(context, result);
    if (proceed != true || !context.mounted) return;
    result = await op(confirmed: true);
    if (!context.mounted || result == null) return;
  }
  if (result case SyncFailed(error: LinkingError.cannotFastForward)
      when pullFallback != null) {
    var pullResult = await pullFallback();
    if (!context.mounted || pullResult == null) return;
    if (pullResult case SyncNeedsConfirmation()) {
      final proceed = await showSyncConfirmDialog(context, pullResult);
      if (proceed != true || !context.mounted) return;
      pullResult = await pullFallback(confirmed: true);
      if (!context.mounted || pullResult == null) return;
    }
    if (pullResult is SyncFailed) {
      // The pull itself didn't clear the way - show what actually went
      // wrong there instead of pretending the original push failure is
      // still the relevant message.
      result = pullResult;
    } else {
      // Pull cleared it - retry the push once. Not recursive (no
      // pullFallback passed through), so a second, different
      // cannotFastForward shows as a plain error rather than looping.
      final retried = await op();
      if (!context.mounted) return;
      result = retried ?? pullResult;
    }
  }
  // 2026-09-24: completion chime (sound_service.dart) - only here, on
  // the user-started path; background auto-sync never comes through
  // _runAndShow, so it stays silent.
  if (repo?.id != null && (result is SyncOk || result is SyncNoChanges)) {
    final wasPush =
        context.read<RepositoryProvider>().lastActionWasPush(repo!.id!);
    unawaited(SoundService.instance
        .play(wasPush ? SoundEvent.push : SoundEvent.pull));
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
  // 2026-09-18: real feedback, live - "Pushed as desktop home screen
  // message stays for a long time... have to wait for the Pushed
  // message to disappear." hideCurrentSnackBar() so this result
  // doesn't queue behind whatever's still showing from a prior action.
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
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
    final provider = context.read<RepositoryProvider>();
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => ConflictsScreen(repo: repo)));
    await provider.refreshConflicts(repo.id!);
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
      title: Text('Sync error', style: TextStyle(color: kStar, fontSize: 16)),
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
          // 2026-09-17: real feedback, live - "Close should be standard
          // across the app... white or green, so it's easy to see."
          // Standardized on white (kStar) everywhere Close appears -
          // see the About dialog's matching Close below.
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.close_rounded, color: kStar, size: 16),
              const SizedBox(width: 4),
              Text('Close', style: TextStyle(color: kStar, fontSize: 15)),
            ],
          ),
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
              style: TextStyle(
                  color: kGreen, fontSize: 15, fontWeight: FontWeight.w700)),
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
// 2026-08-29: real feedback, live - "wrong location, should be in
// About" (the build-number label at the bottom of Settings). That
// label existed specifically so a genuinely-pushed build could be told
// apart from a stale one at a glance (see settings_screen.dart's own
// 2026-08-28 comment on why) - moving it here without fixing what it
// shows would lose that. The version line below used to read the
// hardcoded kAppVersion constant ("0.1.0", no build number, never
// actually reflecting what's installed) - now fetches the real
// PackageInfo first, same as Settings did, so About shows the same
// trustworthy "v0.1.0 (24)" instead of a number that can drift from
// pubspec.yaml unnoticed.
// 2026-09-18: real ask, live - "About, tap logo image and large image
// fades in." A plain full-screen fade (no scrim tap-to-dismiss games,
// just tap anywhere to close) - the point is just seeing the real icon
// artwork bigger, not a gallery viewer.
void _showLargeLogo(BuildContext context) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black87,
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (context, _, __) => GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Center(
        child: Image.asset('assets/icon/icon.png', width: 220, height: 220),
      ),
    ),
    transitionBuilder: (context, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

Future<void> _showAbout(BuildContext context, {required bool paidTier}) async {
  final info = await PackageInfo.fromPlatform();
  if (!context.mounted) return;
  // 2026-09-22 (round 2): real feedback, live - "hearts sway to right
  // edge of text, not phone screen" PERSISTED even after wrapping the
  // Stack in SizedBox(width: double.infinity). Real suspicion: whether
  // SingleChildScrollView's cross axis constraint is actually BOUNDED
  // (my original assumption) or UNBOUNDED (infinity) is genuinely
  // ambiguous without a real device to check, and asking a SizedBox for
  // `double.infinity` width against an ALREADY-infinite incoming
  // constraint is undefined/broken in a way that would silently fail
  // in a release build (no assertions there) rather than throw. An
  // explicit, concrete number sidesteps that ambiguity entirely -
  // BoxConstraints.enforce() clamps a finite request into whatever the
  // incoming range is, bounded or not, so this is correct either way.
  final heartsWidth = MediaQuery.sizeOf(context).width - 128;
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: kSurface,
      // 2026-09-17: same icon the kebab menu's own "About" row already
      // uses (Icons.info_outline, see _MenuRow usage above) - matches
      // what was tapped to open this, same reasoning as Device name's
      // dialog title this session.
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline, color: kTextDim, size: 18),
          const SizedBox(width: 8),
          Text('About', style: TextStyle(color: kStar, fontSize: 16)),
        ],
      ),
      // 2026-09-18: real feedback, live - "SUPPORTS hearts stop at
      // DISCLAIMER, but must reach top." The Stack around SUPPORT below
      // already uses Clip.none so hearts aren't clipped by that
      // immediate row - the real ceiling was this ScrollView's own
      // default Clip.hardEdge, cutting the trail off right at whatever
      // the currently-scrolled viewport's top edge happened to be
      // (DISCLAIMER, when scrolled down far enough to see SUPPORT at
      // all). Clip.none lets the trail actually rise past that edge.
      content: SingleChildScrollView(
        clipBehavior: Clip.none,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 2026-09-17: real ask, live - "svg image replicating real
            // logo." The real app icon itself (assets/icon/icon.png,
            // already the flutter_launcher_icons source), not a
            // hand-traced recreation - guaranteed to match exactly
            // since it IS the logo, not a copy of it.
            Row(
              children: [
                Text('LocalSync',
                    style: TextStyle(
                        color: kStar,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                const SizedBox(width: 10),
                // 2026-09-18: real ask, live - "tap logo image and
                // large image fades in."
                GestureDetector(
                  onTap: () => _showLargeLogo(context),
                  child: Image.asset('assets/icon/icon.png',
                      width: 28, height: 28),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.numbers_outlined, color: kTextMid, size: 13),
                const SizedBox(width: 4),
                Text('v${info.version} (${info.buildNumber})',
                    style: TextStyle(color: kTextMid, fontSize: 13)),
              ],
            ),
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
            const _AboutHeader(icon: Icons.forum_outlined, label: 'CONTACT'),
            const SizedBox(height: 6),
            Text(
              '$kNoteAppName support and FOSS collaboration welcome - '
              'open an issue at codeberg.org/kworld/localsync',
              style: TextStyle(color: kTextMid, fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 20),
            const _AboutHeader(
                icon: Icons.emoji_events_outlined, label: 'CREDITS'),
            const SizedBox(height: 6),
            // 2026-08-23: real feedback, live - "reword to public
            // library CHUV, public library Palais de Rumine, public
            // library Médiathèque Valais Sion Makerspace" - noun-first
            // (matches the house naming rule), and re-clusters all
            // three under "P" instead of being scattered across C/M/P.
            Text(
              // 2026-09-18: real ask, live - "Credits missing Git, if
              // showing Working Copy." Working Copy is the old iOS git
              // client LocalSync actually replaced (superseded
              // 2026-09-04, deleted from the phone) - a stale credit
              // for a tool this app no longer uses at all. Git is the
              // real, live dependency (git2dart FFI bindings, and the
              // desktop script's own git fetch/merge/push) and was
              // simply never added.
              'Bash, Blender, C, C++, Claude, Codemagic, Dart, Eye of '
              'MATE, Flameshot, Flutter, GIMP, Git, iLoader, Inkscape, '
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
                  padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
              onPressed: () => showLicensePage(
                context: context,
                applicationName: 'LocalSync',
                applicationVersion: kAppVersion,
              ),
              // 2026-09-17: real ask, live - "maybe gnu animal?" User
              // sourced the actual file themselves (gnu.org's own
              // gnu-profile.svg, the plain silhouette - the more
              // detailed gnuhead_plain.svg turned illegible at icon
              // scale when both were previewed side by side). Copied
              // in untouched, tinted via colorFilter same as the
              // pairing screen's key/lock icons.
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgPicture.asset('assets/logos/gnu-profile.svg',
                      width: 16,
                      colorFilter: ColorFilter.mode(kGreen, BlendMode.srcIn)),
                  const SizedBox(width: 6),
                  // 2026-09-18: real ask, live - "Open-source
                  // licences, change to FOSS licences?" Matches the
                  // CONTACT section's own "FOSS collaboration welcome"
                  // wording just above - one consistent term instead
                  // of two for the same idea.
                  Text('FOSS licenses',
                      style: TextStyle(color: kGreen, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const _AboutHeader(
                icon: Icons.warning_amber_rounded, label: 'DISCLAIMER'),
            const SizedBox(height: 6),
            // 2026-09-18: real ask, live - "LocalSync syncs your vault
            // (needs terminology for free tier folder too)." kContainerName
            // is hardcoded 'vault' everywhere else in the app (the Tier 1+
            // PKM-aware naming), but Tier 0 (genericFolder) users sync a
            // plain folder, not a vault - reusing the paidTier signal
            // already threaded into this dialog (see the SUPPORT hearts'
            // own use of it) rather than rewording the term globally,
            // which every other kContainerName call site still assumes.
            Text(
              'LocalSync syncs your '
              '${paidTier ? kContainerName : "$kContainerName or folder"} '
              'over your own network - nothing is stored on any server '
              'this app controls. This app is provided as-is, with no '
              'guarantee against data loss.',
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
            Text(
              '1 copy kept off-site (SSD USB enclosure FTW) - LocalSync '
              'it there too, a 3rd device on top of the pair above',
              style: TextStyle(color: kTextMid, fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 20),
            // 2026-08-21: real feedback, live - "where is the manual
            // on the app? I don't see it" (asked twice) - the desktop
            // setup guide (docs/desktop-setup.md) only ever lived in
            // the repo, nothing in the app pointed to it. Same plain-
            // text-URL pattern as CONTACT above, not a new in-app
            // markdown renderer - that's real scope (mermaid support,
            // asset bundling) this doesn't need yet.
            // 2026-09-02: repointed from the Codeberg markdown doc to
            // the real kworld.space/localsync page, live as of today -
            // a one-click "Download for Mac" button + checksummed
            // terminal command, not a wall of prose a new user has to
            // read through to find the actual download.
            const _AboutHeader(
                icon: Icons.menu_book_outlined, label: 'SETUP GUIDE'),
            const SizedBox(height: 6),
            Text(
              'Desktop-side setup (git, SSH, the bare repo) - '
              'kworld.space/localsync',
              style: TextStyle(color: kTextMid, fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 20),
            // 2026-08-23: real feature request, live - "donation link
            // yes." Bitcoin Lightning donation only, not tied to any
            // paid feature or unlock - sidesteps App Store IAP review
            // entirely since nothing in the app is gated by this.
            // Real address applied 2026-08-23 (was a placeholder
            // before that).
            // 2026-09-17: real ask, live - "hearts aren't coming from
            // support they're just near the top. Need to stem from
            // support, like a trail with random spacing, floating
            // upwards." Local Stack, Clip.none so the heart trail can
            // rise above this row's own bounds without being clipped
            // by it - see floating_hearts.dart's own header for the
            // full history of what this replaced.
            // 2026-09-22: real bug, live - "hearts sway to right edge
            // of text, not phone screen." Stack only sizes itself to
            // its NON-positioned children (the SUPPORT label below) -
            // Positioned children don't count toward that. With only
            // `left: 0` set (no `right`), the Positioned's own max
            // width was capped at `stackWidth - left`, and stackWidth
            // was just the SUPPORT label's own narrow width - so
            // FloatingHearts was being squeezed down to that, no matter
            // what trailWidth it was actually given. SizedBox(width:
            // heartsWidth) forces the Stack itself to take this
            // explicit, concrete width instead of shrink-wrapping to
            // its narrowest child - see this function's own
            // `heartsWidth` comment above for why a concrete number
            // replaced the first attempt's `double.infinity`.
            SizedBox(
              width: heartsWidth,
              child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  bottom: 24,
                  left: 0,
                  right: 0,
                  // 2026-09-18: real feedback, live (round 2) - "Hearts
                  // floating stop at credits, but should go to v0.0
                  // height." 420 only reached CREDITS, three sections up
                  // from SUPPORT - measured the real distance from the
                  // version line's own bottom edge to SUPPORT's bottom
                  // edge with a throwaway test replica of this exact
                  // Column (real text, real spacing): 1047px. Minus the
                  // 24px bottom offset above, 1023px is the real minimum
                  // to reach the version line - 1050 clears it with a
                  // small margin instead of stopping just short again.
                  // 2026-09-18: real ask, live - "Support floating
                  // hearts decrease per higher tiers." See this
                  // dialog's own paidTier param doc (call site above)
                  // for why paid-vs-free is the real granularity
                  // available today.
                  //
                  // 2026-09-22: real ask, live - "hearts need to slide
                  // until reaching the left or right phone edges."
                  // AlertDialog's real defaults (Flutter framework,
                  // unchanged by this dialog): insetPadding 40px each
                  // side, contentPadding 24px each side - screen width
                  // minus both gives this dialog's real usable content
                  // width, which is what the tilt-glide should now
                  // reach edge to edge. Idle sway stays anchored near
                  // SUPPORT regardless of this value - see
                  // FloatingHearts' own trailWidth doc and
                  // _HeartsPainter's _restWidth.
                  child: FloatingHearts(
                      color: kGreen,
                      trailHeight: 1050,
                      trailWidth: heartsWidth,
                      quiet: paidTier),
                ),
                const _AboutHeader(
                    icon: Icons.favorite_outline,
                    label: 'SUPPORT',
                    // 2026-09-18: real ask, live - "SUPPORT have heart
                    // change from grey to green fading like a heart
                    // beat." Every other _AboutHeader icon stays the
                    // plain static kTextDim grey (pulse defaults false) -
                    // only SUPPORT's heart pulses, since only SUPPORT is
                    // actually about the donation trail rising beside it.
                    pulse: true),
              ],
              ),
            ),
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 2026-09-17, corrected same day - kTextDim read as "too
              // dark, hard to see." Real feedback: Close should be
              // standardized app-wide, white so it's always easy to
              // read - matches the other Close dialog now too.
              Icon(Icons.close_rounded, color: kStar, size: 16),
              const SizedBox(width: 4),
              Text('Close', style: TextStyle(color: kStar, fontSize: 15)),
            ],
          ),
        ),
      ],
    ),
  );
}

// 2026-09-17: shared icon+label row for the About dialog's alphabetized
// section headers (CONTACT/CREDITS/DISCLAIMER/SETUP GUIDE/SUPPORT) -
// one widget instead of repeating the same TextStyle five times, real
// ask this session to add images to all of them.
class _AboutHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  // 2026-09-18: real ask, live - "SUPPORT have heart change from grey
  // to green fading like a heart beat." Opt-in, not a blanket change -
  // every other section header (CONTACT/CREDITS/DISCLAIMER/SETUP GUIDE)
  // keeps its plain static kTextDim icon.
  final bool pulse;
  const _AboutHeader(
      {required this.icon, required this.label, this.pulse = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        pulse ? _HeartbeatIcon(icon: icon) : Icon(icon, color: kTextDim, size: 13),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                color: kTextDim,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5)),
      ],
    );
  }
}

// 2026-09-18: real ask, live - "SUPPORT have heart change from grey to
// green fading like a heart beat." Color-lerps between kTextDim (grey,
// matching every other section header) and kGreen on a repeating
// fade, instead of a static color - reads as a pulse, not a blink,
// since it's a smooth color transition rather than an on/off toggle.
class _HeartbeatIcon extends StatefulWidget {
  final IconData icon;
  const _HeartbeatIcon({required this.icon});

  @override
  State<_HeartbeatIcon> createState() => _HeartbeatIconState();
}

class _HeartbeatIconState extends State<_HeartbeatIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
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
      builder: (_, __) => Icon(widget.icon,
          color: Color.lerp(
              kTextDim, kGreen, Curves.easeInOut.transform(_ctrl.value)),
          size: 13),
    );
  }
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

// 2026-09-09: same state order as _StatusIcon.build below, kept as one
// small function instead of duplicated inline so the two can't drift
// apart - the icon shown and the words describing it need to always
// agree, this is what a real "what does this mean" tap is for.
String _securityStatusLabel(List<Repository> repos) {
  if (repos.isEmpty) return '';
  final hasError = repos.any((r) => r.status == SyncStatus.error);
  final hasSyncing = repos.any((r) => r.status == SyncStatus.syncing);
  final allOk = repos.every((r) => r.status == SyncStatus.ok);

  if (hasSyncing) return 'Syncing now';
  if (hasError) return 'Sync error - tap Security for details';
  if (allOk) return 'Secure - up to date';
  return 'Not yet synced';
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
      // 2026-09-18: real feedback, live - "Security image is often amber
      // with sync arrows, indicating a problem, but this is just the
      // correct operation of the app, syncing." Kept amber (removing it
      // would lose the at-a-glance "still working" signal entirely) but
      // now spins continuously while syncing - motion reads as "active,"
      // not "stuck/warning," the same problem color alone was causing.
      return const _SpinningSyncIcon();
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

// 2026-09-18: real ask, live - amber Icons.sync now rotates continuously
// while syncing (see _StatusIcon's own 2026-09-18 comment). Icons.sync
// has 180-degree rotational symmetry, so a full turn reads as two
// identical half-spins - still smooth, no visible seam.
class _SpinningSyncIcon extends StatefulWidget {
  const _SpinningSyncIcon();

  @override
  State<_SpinningSyncIcon> createState() => _SpinningSyncIconState();
}

class _SpinningSyncIconState extends State<_SpinningSyncIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1, milliseconds: 200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _ctrl,
      child: const Icon(Icons.sync, color: Colors.amber, size: 22),
    );
  }
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

    // 2026-08-30, corrected - "object 2 [name] isn't spread right of
    // object 1 [logo] and left of object 3 [kebab]." The name needs to
    // actually SPAN that space, not sit at a small fixed width with
    // blank space left over. Expanded on both this Row and the name Text
    // does that with the real leftover width - no fixed cap, no
    // computed-constant to get wrong again.
    return Row(
      key: const ValueKey('appBarRepoStatusRow'),
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              if (hasError) {
                _showFullError(context, repo);
              } else {
                onTap();
              }
            },
            child: Padding(
              // 2026-08-30: real feedback, live - "object 2 not close
              // enough to object 3." Dropped the right-side inset - it
              // was just eating into the name box's real reach toward
              // the kebab for no visual reason (nothing sits flush
              // against that edge to justify it).
              padding: const EdgeInsets.only(left: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    // 2026-08-28, follow-up real feedback, live - "possible
                    // to vertically centre?" The dot used a manual top-2px
                    // nudge tuned for single-line text only; once the name
                    // wraps to 2 lines that nudge left it pinned near the
                    // top instead of centred against the taller block.
                    // Plain .center cross-axis alignment centres it against
                    // whatever height the name actually ends up being,
                    // 1 line or 2, no manual offset needed.
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      isSyncing
                          ? const _SpinningSync()
                          : _StatusDot(status: repo.status),
                      const SizedBox(width: 6),
                      // 2026-08-30: Expanded spans the real leftover
                      // width between the logo and the kebab (object 2
                      // spread between object 1 and object 3) - left-
                      // aligned by default, so a short name starts right
                      // after the dot and a long name gets the real
                      // room to wrap/not truncate.
                      Expanded(
                        child: Text(
                          repo.name,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: kStar,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              height: 1.2),
                          overflow: TextOverflow.ellipsis,
                          softWrap: true,
                          maxLines: 2,
                        ),
                      ),
                    ],
                  ),
                  // 2026-09-18: real feedback, live - "Errors when
                  // syncing under the top title bar are too small to
                  // read, can you move to the bottom snack bar to make
                  // larger." This used to show repo.lastError here at
                  // 10px, truncated to one line - removed outright, not
                  // resized, since the real fix is showing it somewhere
                  // that actually fits: both the manual push/pull path
                  // (_runAndShow) and the auto-launch pull (this
                  // screen's own pendingAutoSyncFailure handling above)
                  // already show the same diagnosis in a real 16px
                  // bottom SnackBar. The status dot above still turns
                  // red/error-colored, and tapping this whole row still
                  // opens the full error dialog (_showFullError) - only
                  // the redundant, cramped inline copy is gone.
                  if (isSyncing)
                    Row(
                      children: [
                        // Mirrors the name row's leading _SpinningSync
                        // (14px) + 6px gap above, so this line centers
                        // within the same span the name does - a plain
                        // full-width center here would center across
                        // the whole row including that 20px the name
                        // row doesn't have, landing visibly left of it.
                        const SizedBox(width: 20),
                        Expanded(
                          child: Text(repo.syncPhase.label,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: kTextMid, fontSize: 10)),
                        ),
                      ],
                    ),
                  // 2026-08-28: real feedback, live - "remove the synced
                  // just now" - dropped the idle-state "synced Xm ago"
                  // line entirely; error/syncing status above are
                  // unaffected, only asked to remove this one.
                ],
              ), // closes Column
            ), // closes Padding
          ), // closes GestureDetector
        ), // closes Expanded
        // dropdown sibling, if a second repo exists.
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
          // 2026-08-29: real feedback, live - "loads of available
          // black space left of the kebab icon" even with a real
          // vault linked and its name showing. Same root cause as
          // the kebab's own 2026-08-29 fix: this button's icon is
          // only 20px but PopupMenuButton enforces Material's
          // default 48x48 minimum tap target regardless, and no
          // padding override was ever set here either - shrinkWrap
          // removes that, freeing real width back to the name area.
          // 2026-08-30: name area is now Expanded (see above), so this
          // no longer needs to be accounted for in any width math -
          // Expanded automatically leaves it exactly the room it needs.
          Theme(
            data: Theme.of(context).copyWith(
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: PopupMenuButton<int>(
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
