// main.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:git2dart/git2dart.dart';
import 'package:path_provider/path_provider.dart';
import 'theme.dart';
import 'services/repository_provider.dart';
import 'features/linking/linking_controller.dart';
import 'lifecycle_observer.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PlatformSpecific.initialize();
  final localVaultPath = (await getApplicationDocumentsDirectory()).path;
  runApp(SynclocalApp(localVaultPath: localVaultPath));
}

class SynclocalApp extends StatefulWidget {
  final String localVaultPath;
  const SynclocalApp({super.key, required this.localVaultPath});

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
      desktopIp:      '172.20.10.6',
      bareRepoPath:   '/home/rapi5/Documents/Git_bare_repo/Md_files_bare.git',
      localVaultPath: widget.localVaultPath,
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
