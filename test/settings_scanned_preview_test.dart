// Local visual verification only - Settings right after a complete QR scan:
// yellow box says Desktop found, fields 1-4 carry FROM QR tags
// (settings_screen.dart). Run with:
//   flutter test test/settings_scanned_preview_test.dart --update-goldens
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:localsync/features/linking/linking_controller.dart';
import 'package:localsync/screens/settings_screen.dart';
import 'package:localsync/services/repository_provider.dart';
import 'package:localsync/services/theme_service.dart';
import 'package:localsync/theme.dart';

void main() {
  testWidgets('scanned: Desktop found, FROM QR on each field', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), (c) async => '/tmp');
    m.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity'), (c) async => ['none']);
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ctrl = LinkingController(desktopUser: '', desktopIp: '', bareRepoPath: '');
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: ctrl),
        ChangeNotifierProvider.value(value: RepositoryProvider()),
        ChangeNotifierProvider.value(value: ThemeService()),
      ],
      child: MaterialApp(
          theme: buildAppTheme(),
          home: const SettingsScreen(neededForPairing: true)),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    (tester.state(find.byType(SettingsScreen)) as dynamic).debugShowScanned([
      'rapi5',
      '172.20.10.2',
      '/home/rapi5/Documents/Git/pi5-obsidian/Git_bare_repo/Md_files_bare.git',
      '/home/rapi5/Documents/Obsidian_vault',
    ]);
    await tester.pump(const Duration(milliseconds: 700));
    while (tester.takeException() != null) {}
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/settings_scanned.png'));
  });
}
