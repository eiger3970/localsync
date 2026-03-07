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
      desktopUser:  'rapi5',
      desktopIp:    '172.20.10.6',
      bareRepoPath: '/home/rapi5/Documents/Git_bare_repo/Md_files_bare.git',
      vaultName:    'Obsidian_phone_vault',
      repoName:     'Md_files_bare',
      sshPort:      22,
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
