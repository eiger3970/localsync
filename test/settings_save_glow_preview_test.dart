// Local visual verification only - Save glows once the pairing fields
// are filled (settings_screen.dart). Run with:
//   flutter test test/settings_save_glow_preview_test.dart --update-goldens
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:localsync/features/linking/linking_controller.dart';
import 'package:localsync/screens/settings_screen.dart';
import 'package:localsync/services/repository_provider.dart';
import 'package:localsync/services/theme_service.dart';

void main() {
  testWidgets('Save glows when fields are filled', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'),
        (c) async => '/tmp');
    m.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity'), (c) async => ['none']);
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ctrl = LinkingController(
        desktopUser: 'rapi5',
        desktopIp: '172.20.10.11',
        bareRepoPath: '/home/rapi5/Documents/Git/pi5-obsidian/Git_bare_repo/Md_files_bare.git');
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: ctrl),
        ChangeNotifierProvider.value(value: RepositoryProvider()),
        ChangeNotifierProvider.value(value: ThemeService()),
      ],
      child: const MaterialApp(home: SettingsScreen(neededForPairing: true)),
    ));
    await tester.pump(const Duration(milliseconds: 700));
    while (tester.takeException() != null) {}
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/settings_save_glow.png'));
  });
}
