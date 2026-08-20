// main.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme.dart';
import 'services/repository_provider.dart';
import 'features/linking/linking_controller.dart';
import 'lifecycle_observer.dart';
import 'screens/home_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _linkingController = LinkingController(
      desktopUser:    'rapi5',
      // This hardcoded desktopIp drifts every time the phone's hotspot
      // reassigns DHCP addresses (no settings screen yet to configure
      // it on-device) - re-check against the desktop's actual
      // wlan0/eth1 address each session (`ip -4 addr show`) if pairing
      // fails with a connection error.
      //
      // localVaultPath removed 2026-08-09: the vault folder is no
      // longer a fixed app-owned path computed once at startup - it's
      // the user's own Obsidian vault folder, selected during setup via
      // VaultFolderService's native picker and tracked per-Repository
      // (see models/repository.dart's vaultBookmark field). See
      // lib/STRUCTURE.md for the full architecture correction.
      desktopIp:      '172.20.10.11',
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
      ],
      child: MaterialApp(
        title: 'localsync',
        theme: appTheme,
        debugShowCheckedModeBanner: false,
        home: const HomeScreen(),
      ),
    );
  }
}
