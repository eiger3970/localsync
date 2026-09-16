// main.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:url_launcher/url_launcher.dart';
import 'theme.dart';
import 'services/database_service.dart';
import 'services/repository_provider.dart';
import 'services/theme_service.dart';
import 'services/purchase_service.dart';
import 'features/linking/linking_controller.dart';
import 'lifecycle_observer.dart';
import 'screens/home_screen.dart';
import 'widgets/auto_sync_on_resume.dart';
import 'widgets/flag_backdrop.dart';
import 'widgets/flag_frame.dart';

// 2026-09-15: real feedback, live - a resolved-conflict banner's own
// UNDO/view-backup link stopped responding once the screen that first
// showed it (Conflicts) got popped back to Home underneath it - "Keep
// Both didn't take me to the home page... View or restore ... this
// should be a tappable link." MaterialBanner itself is genuinely
// screen-independent (MaterialApp wraps one ScaffoldMessenger shared by
// every route, which is exactly why the banner kept showing after
// popping back) - but every action closure on it still captured
// Conflicts screen's own BuildContext, which goes stale the instant
// that screen is disposed. rootNavigatorKey gives any such closure a
// context that survives regardless of which screen triggered it,
// instead of one tied to a screen about to disappear underneath it.
final rootNavigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 2026-08-20: "white screen took about 5 seconds" - git2dart's own
  // native libgit2 load used to be awaited here, before runApp() -
  // blocking even the first Flutter frame. Now deferred and memoized
  // inside GitServiceImpl (services/git_service.dart), lazily run right
  // before the first real git operation instead of up front.
  runApp(const LocalSyncApp());
}

class LocalSyncApp extends StatefulWidget {
  const LocalSyncApp({super.key});

  @override
  State<LocalSyncApp> createState() => _LocalSyncAppState();
}

class _LocalSyncAppState extends State<LocalSyncApp> {
  late final LinkingController      _linkingController;
  late final LocalSyncLifecycleObserver _lifecycleObserver;
  // 2026-09-16: was created inline via MultiProvider's `create:` below -
  // moved to a field, same pattern as _linkingController/_themeService/
  // _purchaseService, so initState() can reach it directly to wire up
  // Quick Actions (QuickActions().initialize needs a real instance to
  // call setPendingQuickAction on, and runs before the provider tree
  // below ever builds).
  final RepositoryProvider _repositoryProvider = RepositoryProvider();
  final QuickActions _quickActions = const QuickActions();
  // 2026-08-21: "skins" IAP - loads the saved palette (or falls back
  // to the free default) fire-and-forget, same pattern as the
  // desktopIp/bareRepoPath overrides below - there's always some UI
  // time before the first frame that matters visually.
  final ThemeService _themeService = ThemeService();
  // 2026-08-21: real RevenueCat key now set (kRevenueCatApiKey in
  // purchase_service.dart) - init() actually connects for the first
  // time. Fire-and-forget, same reasoning as everything else in this
  // method - the SDK config call doesn't need to block the first frame.
  final PurchaseService _purchaseService = PurchaseService();

  @override
  void initState() {
    super.initState();
    _themeService.load();
    _purchaseService.init();
    _linkingController = LinkingController(
      // 2026-08-28: build-time fallback only, now overridable via the
      // Settings screen (same pattern as desktopIp/bareRepoPath below).
      // Blanked to empty (was this developer's own real desktop login,
      // 'rapi5') - same "personal info leaking into a fresh install's
      // default" fix as desktopIp/bareRepoPath below.
      desktopUser:    '',
      // localVaultPath removed 2026-08-09: the vault folder is no
      // longer a fixed app-owned path computed once at startup - it's
      // the user's own Obsidian vault folder, selected during setup via
      // VaultFolderService's native picker and tracked per-Repository
      // (see models/repository.dart's vaultBookmark field). See
      // lib/STRUCTURE.md for the full architecture correction.
      //
      // 2026-08-20: this build-time value is now only the fallback for
      // a first run - RepositoryProvider.getDesktopIp() below overrides
      // it with whatever the user has saved via the Settings dialog
      // (home_screen.dart), so a real network drift no longer needs a
      // code edit and rebuild to fix. Re-verified against `ip -4 addr
      // show` at time of writing (phone was on hotspot/WiFi, wlan0).
      //
      // 2026-08-28: real feedback, live - "I don't understand why this
      // is still mentioning obsidian, tier0 users need simple terms."
      // This build-time fallback used to be this developer's own real
      // desktop IP/path (172.20.10.11, .../pi5-obsidian/...) - meaning
      // any fresh install, real customer or Tier 0 tester alike, saw
      // this developer's personal desktop info pre-filled in Settings
      // before ever configuring anything. Blanked to empty strings -
      // Stage 1's own _needsSettings check (linking_screen.dart) already
      // handles the "nothing configured yet" case correctly (shows a
      // Settings reminder before any pairing attempt), so an empty
      // fallback is the actually-correct default, not a regression.
      desktopIp:      '',
      // 2026-08-28: same reasoning as desktopIp above - was this
      // developer's own real bare repo path, now blank so a fresh
      // install never sees another user's desktop folder structure.
      bareRepoPath:   '',
      sshPort:        22,
    );
    // Applies saved desktopIp/bareRepoPath overrides, if the user has
    // ever set them via the Settings screen - fire-and-forget, there's
    // always some UI time before a real link attempt could race this.
    // Falls back to the build-time defaults above on first run (nothing
    // saved yet).
    DatabaseService().getDesktopUser().then((saved) {
      if (saved != null && saved.trim().isNotEmpty) {
        _linkingController.updateDesktopUser(saved.trim());
      }
    });
    DatabaseService().getDesktopIp().then((saved) {
      if (saved != null && saved.trim().isNotEmpty) {
        _linkingController.updateDesktopIp(saved.trim());
      }
    });
    DatabaseService().getBareRepoPath().then((saved) {
      if (saved != null && saved.trim().isNotEmpty) {
        _linkingController.updateBareRepoPath(saved.trim());
      }
    });
    DatabaseService().getDesktopVaultPath().then((saved) {
      if (saved != null && saved.trim().isNotEmpty) {
        _linkingController.updateDesktopVaultPath(saved.trim());
      }
    });
    _lifecycleObserver = LocalSyncLifecycleObserver(
      linkingController: _linkingController,
    );
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    // 2026-09-16: real feedback, live - "Push and Pull also on right
    // click." Fires from a cold launch (app wasn't running) or a warm
    // one (already running) - either way there's no HomeScreen
    // BuildContext to call _runAndShow on directly from here, so this
    // only sets a flag on the provider; HomeScreen's own build() (same
    // postFrameCallback pattern as pendingConflictRepoId) does the
    // actual push/pull once it exists, through the same _runAndShow
    // every other push/pull already goes through - same confirm
    // dialogs, same SnackBar feedback, nothing bypassed.
    _quickActions.initialize((type) {
      if (type == 'action_push' || type == 'action_pull') {
        _repositoryProvider.setPendingQuickAction(type);
      } else if (type == 'action_feedback') {
        // 2026-09-16: real feedback, live - "tap-to-feedback behaviour
        // kworld.space/feedback." /feedback doesn't exist on the site
        // (confirmed 404 live) - /contact does, and is a real working
        // form (src/pages/contact.tsx), not a stub, so this points
        // there instead of a page that would just 404 for the user.
        // ?app=localsync&service=Bug+report: the plain /contact form is
        // a freelance-inquiry page (budget/timeline chips, CHF amounts)
        // - real risk flagged live ("too intimidated seeing the page
        // for business people") - these params trigger contact.tsx's
        // own app-feedback mode instead (hides budget/timeline, swaps
        // in app-feedback copy), same submission pipeline underneath.
        launchUrl(
            Uri.parse(
                'https://kworld.space/contact?app=localsync&service=Bug+report'),
            mode: LaunchMode.externalApplication);
      }
    });
    _quickActions.setShortcutItems(const [
      // 2026-09-16: real feedback, live - custom icons instead of the
      // default blank/system look. Diagonal (not straight up/down) per
      // direct ask - arrow toward where the desktop conceptually sits
      // (up-right) for push, toward the phone (down-left) for pull.
      // Confirmed real-device (2026-09-16, later same day): iOS always
      // renders these as a plain black/white template mask regardless
      // of the asset's own render-intent setting - the green in the
      // source SVGs never actually shows in the real menu, only the
      // arrow shape does. See QuickActionRemove's own note below for
      // the full explanation.
      ShortcutItem(
        type: 'action_pull',
        localizedTitle: 'Pull',
        icon: 'QuickActionPull',
      ),
      ShortcutItem(
        type: 'action_push',
        localizedTitle: 'Push',
        icon: 'QuickActionPush',
      ),
      // 2026-09-16: real feedback, live - "this warning can be added to
      // the app icon," same pattern as Working Copy's own "Deletion
      // warning" item on its long-press menu (confirmed earlier this
      // session: that's a ShortcutItem's localizedSubtitle, not an
      // override of iOS's own Remove App dialog - no app can touch
      // that). Purely informational (no `type` handling needed below -
      // tapping it just opens the app normally, same as any unhandled
      // type). Wording is deliberately scoped to what the architecture
      // actually guarantees (the vault folder is Obsidian's own
      // storage, not this app's sandbox - see lib/STRUCTURE.md), not
      // guessed specifics about SSH keys/pairing state that have never
      // been confirmed against a real uninstall.
      ShortcutItem(
        type: 'info_uninstall',
        // 2026-09-16: real feedback, live - "use same language as
        // Apple" - matches the native menu's own "Remove App" wording
        // directly instead of a generic "Before you remove..." lead-in.
        // Shield emoji prefixed on the title (moved from the subtitle,
        // per direct ask - "add shield left of Remove App warning") -
        // the closest thing to "a 2nd image" this slot allows, since
        // the icon field itself only holds one image (the no-entry
        // circle below), and iOS renders emoji in their own fixed
        // artwork, unaffected by the template-masking that flattens
        // the icon field to plain black/white (see main.dart's own
        // note on QuickActionRemove/Pull/Push/Feedback below).
        localizedTitle: '🛡️ Remove App warning',
        // 2026-09-16: real feedback, live - "text to address free and
        // paid users." Free: notes live in Obsidian's own storage, not
        // this app's sandbox (architectural fact, lib/STRUCTURE.md).
        // Paid: IAP entitlements are tied to the Apple ID via
        // RevenueCat/StoreKit, not local app data - restorable after
        // reinstall the same way any App Store purchase is. Both real
        // guarantees, not guessed - kept to what's actually true rather
        // than reassurance for its own sake.
        localizedSubtitle:
            "Notes & purchases stay safe - just re-pair after",
        // 2026-09-16: no-entry circle shape matches Apple's own
        // delete-badge glyph language, per explicit ask. Amber was the
        // final color pick, but confirmed real-device: iOS always
        // renders Quick Action icons as a plain black/white template
        // mask (UIApplicationShortcutIcon's own documented behavior,
        // not something the asset catalog's own render-intent setting
        // can override) - only the SHAPE survives, not the color. The
        // 🛡️ emoji above is the one thing actually carrying color.
        icon: 'QuickActionRemove',
      ),
      // 2026-09-16: real feedback, live - "4th line... tap-to-feedback
      // behaviour kworld.space/feedback." Unlike the warning item above,
      // this one IS actionable - see the `action_feedback` branch in
      // initialize() above, which opens kworld.space/contact (the real
      // working page - /feedback itself 404s). Smiley face, not dots,
      // per direct ask (legible detail at the menu's small render size
      // was the deciding factor) - green in the source SVG, though
      // that never actually shows in the real menu (see the Pull/Push
      // note above - iOS always template-masks these to black/white).
      ShortcutItem(
        type: 'action_feedback',
        localizedTitle: 'Send feedback',
        localizedSubtitle: 'kworld.space/contact',
        icon: 'QuickActionFeedback',
      ),
    ]);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    _linkingController.dispose();
    // 2026-09-16: .value() (needed so initState can reach this instance
    // for Quick Actions, see above) does NOT auto-dispose the way the
    // old create: factory did - has to happen here now instead.
    _repositoryProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _repositoryProvider),
        ChangeNotifierProvider.value(value: _linkingController),
        ChangeNotifierProvider.value(value: _themeService),
        Provider.value(value: _purchaseService),
      ],
      // 2026-08-21: "skins" IAP - MaterialApp's theme has to be
      // rebuilt (buildAppTheme() called fresh) every time the
      // selected palette changes, not just read once - this Consumer
      // is what actually cascades a skin change through the whole
      // tree, since AppTheme.current is a plain static value with no
      // notification of its own.
      child: Consumer<ThemeService>(
        builder: (_, themeService, __) => MaterialApp(
          navigatorKey: rootNavigatorKey,
          title: 'localsync',
          theme: buildAppTheme(),
          debugShowCheckedModeBanner: false,
          // 2026-08-22: was `body: FlagFrame(...)` inside just
          // home_screen.dart's Scaffold - real scope gap, every other
          // screen (Settings, Commit, Conflicts, Pairing, Linking, the
          // kebab menu) had no skin decoration at all. `builder` wraps
          // the Navigator itself, so this now applies to every route
          // and every dialog/popup drawn above it, with zero
          // per-screen wiring. FlagBackdrop (void fill + bold skins'
          // tiled mini-flags) sits behind FlagFrame (the edge border)
          // - both painted, neither ever drawn over `child`'s actual
          // content.
          builder: (context, child) => FlagBackdrop(
            child: FlagFrame(child: child ?? const SizedBox.shrink()),
          ),
          // 2026-08-21: real bug, live - "Red is the main page and
          // Settings page has the blue." This was `const HomeScreen()`
          // - Flutter can treat a const widget as identical across
          // rebuilds and skip rebuilding it entirely, even when this
          // Consumer's own rebuild changed MaterialApp's theme. Home
          // (never explicitly rebuilt after the very first time) kept
          // showing whichever skin was active back then, while
          // Settings (freshly pushed via Navigator each time, never
          // const) correctly re-rendered live. Removing const forces
          // Home to actually rebuild - and re-read the live kGreen/
          // kVoid/etc getters - every time the skin changes.
          // 2026-09-06: AutoSyncOnResume wraps HomeScreen now (see that
          // widget's own doc comment) - kept HomeScreen() itself non-
          // const, same as before this change, for the exact reason the
          // comment above used to explain here: a const HomeScreen can
          // get treated as identical across rebuilds and skip re-reading
          // the live skin colors when only this Consumer's theme
          // actually changed.
          home: AutoSyncOnResume(child: HomeScreen()), // ignore: prefer_const_constructors
        ),
      ),
    );
  }
}
