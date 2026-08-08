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

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Diagnostic boot screen (2026-08-08): first real-device run hung on a
  // white screen indefinitely, no crash, process stayed alive - meaning
  // something in the old main()'s pre-runApp async init (PlatformSpecific
  // .initialize() eagerly loading git2dart's native lib, or
  // getApplicationDocumentsDirectory()) was blocking before any UI ever
  // drew. Release builds don't reliably surface print()/debugPrint() in
  // the device syslog, so rather than guess blind, runApp() now happens
  // immediately with each init step run afterward and its status shown
  // directly on screen - gives a definitive answer without needing
  // syslog to cooperate. Remove this once a real device run succeeds
  // cleanly and revert to the plain async main() + runApp(SynclocalApp).
  runApp(const _BootScreen());
}

class _BootScreen extends StatefulWidget {
  const _BootScreen();

  @override
  State<_BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<_BootScreen> {
  String _status = 'Starting…';
  String? _error;
  String? _localVaultPath;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      setState(() => _status = 'PlatformSpecific.initialize()…');
      await PlatformSpecific.initialize();

      setState(() => _status = 'getApplicationDocumentsDirectory()…');
      final localVaultPath = (await getApplicationDocumentsDirectory()).path;

      setState(() => _status = 'Done - launching app');
      setState(() => _localVaultPath = localVaultPath);
    } catch (e, st) {
      setState(() {
        _error = '$e\n\n$st';
        _status = 'Failed';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_localVaultPath != null) {
      return SynclocalApp(localVaultPath: _localVaultPath!);
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_status,
                    style: const TextStyle(color: Colors.white, fontSize: 16)),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
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
