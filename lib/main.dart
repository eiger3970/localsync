// main.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme.dart';
import 'services/database_service.dart';
import 'services/repository_provider.dart';
import 'services/theme_service.dart';
import 'services/purchase_service.dart';
import 'features/linking/linking_controller.dart';
import 'lifecycle_observer.dart';
import 'screens/home_screen.dart';
import 'widgets/flag_backdrop.dart';
import 'widgets/flag_frame.dart';

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
      desktopUser:    'rapi5',
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
      desktopIp:      '172.20.10.2',
      // 2026-08-20: real production repo, replacing Working Copy - the
      // conflict-resolution concern that held this back earlier today
      // is now closed (3-for-3 real-device revert test, plus the full
      // test checklist: Kanban conflicts, deletion-safety, auto/manual
      // toggle, auto-sync-on-launch). Fresh mirror backup taken
      // immediately before this switch (Md_files_bare_backup_
      // 202608201534.git, HEAD unchanged since the morning's backup -
      // no activity missed) and a plain-folder vault copy from earlier
      // today, both independent of anything this app does going
      // forward.
      bareRepoPath:   '/home/rapi5/Documents/Git/pi5-obsidian/Git_bare_repo/Md_files_bare.git',
      sshPort:        22,
    );
    // Applies saved desktopIp/bareRepoPath overrides, if the user has
    // ever set them via the Settings screen - fire-and-forget, there's
    // always some UI time before a real link attempt could race this.
    // Falls back to the build-time defaults above on first run (nothing
    // saved yet).
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
    _lifecycleObserver = LocalSyncLifecycleObserver(
      linkingController: _linkingController,
    );
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    _linkingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => RepositoryProvider()),
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
          home: HomeScreen(), // ignore: prefer_const_constructors
        ),
      ),
    );
  }
}
