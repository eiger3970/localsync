// Local visual verification only - the final "Your notes have arrived!"
// screen (linking_screen.dart _CompleteView). Run with:
//   flutter test test/complete_view_preview_test.dart --update-goldens
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:localsync/features/linking/linking_controller.dart';
import 'package:localsync/screens/linking_screen.dart';
import 'package:localsync/services/repository_provider.dart';
import 'package:localsync/services/theme_service.dart';
import 'package:localsync/theme.dart';

void main() {
  testWidgets('final install screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), (c) async => '/tmp');
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ctrl = LinkingController(desktopUser: 'rapi5', desktopIp: '172.20.10.2', bareRepoPath: '')
      ..debugLastVaultBackupRelPath = '.localsync_backups/Backup 202609301030';
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: ctrl),
        ChangeNotifierProvider.value(value: RepositoryProvider()),
        ChangeNotifierProvider.value(value: ThemeService()),
      ],
      child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
              backgroundColor: kVoid,
              // 2026-10-06: bounded like the app (Expanded > AnimatedSwitcher).
              body: completeViewForPreview(ctrl))),
    ));
    await tester.pump(const Duration(seconds: 2));
    while (tester.takeException() != null) {}
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/complete_view.png'));
  });
  testWidgets('existing vault: final install screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), (c) async => '/tmp');
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ctrl = LinkingController(desktopUser: 'rapi5', desktopIp: '172.20.10.2', bareRepoPath: '')
      ..debugLastVaultBackupRelPath = '.localsync_backups/Backup 202609301030'
      ..linkExisting = true;
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: ctrl),
        ChangeNotifierProvider.value(value: RepositoryProvider()),
        ChangeNotifierProvider.value(value: ThemeService()),
      ],
      child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
              backgroundColor: kVoid,
              // 2026-10-06: bounded like the app (Expanded > AnimatedSwitcher).
              body: completeViewForPreview(ctrl))),
    ));
    await tester.pump(const Duration(seconds: 2));
    while (tester.takeException() != null) {}
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/complete_view_existing.png'));
  });
}
