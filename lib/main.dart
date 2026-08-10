// main.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:git2dart/git2dart.dart';
import 'theme.dart';
import 'services/repository_provider.dart';
import 'features/linking/linking_controller.dart';
import 'lifecycle_observer.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PlatformSpecific.initialize();
  runApp(const SynclocalApp());
}

class SynclocalApp extends StatefulWidget {
  const SynclocalApp({super.key});

  @override
  State<SynclocalApp> createState() => _SynclocalAppState();
}

class _SynclocalAppState extends State<SynclocalApp> {
  late final LinkingController      _linkingController;
  late final SynclocalLifecycleObserver _lifecycleObserver;

  @override
  void initState() {
    super.initState();
    _linkingController = LinkingController(
      desktopUser:    'rapi5',
      // Both values below were wrong until 2026-08-09: this hardcoded
      // desktopIp drifts every time the phone's hotspot reassigns DHCP
      // addresses (no settings screen yet to configure it on-device) -
      // re-check against the desktop's actual wlan0/eth1 address each
      // session. bareRepoPath was pointing at a path that never
      // existed; the real bare repo synco.sh and the desktop's actual
      // Obsidian vault use is at Git/pi5-obsidian/Git_bare_repo/.
      //
      // localVaultPath removed 2026-08-09: the vault folder is no
      // longer a fixed app-owned path computed once at startup - it's
      // the user's own Obsidian vault folder, selected during setup via
      // VaultFolderService's native picker and tracked per-Repository
      // (see models/repository.dart's vaultBookmark field). See
      // lib/STRUCTURE.md for the full architecture correction.
      desktopIp:      '172.20.10.11',
      // Points at an isolated test bare repo (detached clone of
      // Md_files_bare.git, no remote back to production) so untested
      // push/reset logic can't touch the real vault sync. Switch back
      // to Md_files_bare.git only once push has been verified safe.
      bareRepoPath:   '/home/rapi5/Documents/Git/pi5-obsidian/Git_bare_repo/synclocal_test.git',
      sshPort:        22,
    );
    _lifecycleObserver = SynclocalLifecycleObserver(
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
        title: 'synclocal',
        theme: appTheme,
        debugShowCheckedModeBanner: false,
        home: const HomeScreen(),
      ),
    );
  }
}
