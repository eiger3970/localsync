// Local visual verification only. Renders the real SettingsScreen with
// one linked vault, scrolled to the LOCALSYNC FOLDER card, with a new
// folder typed in but not saved yet. Run with:
//   flutter test test/localsync_folder_card_preview_test.dart --update-goldens
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:localsync/features/linking/linking_controller.dart';
import 'package:localsync/models/repository.dart';
import 'package:localsync/screens/settings_screen.dart';
import 'package:localsync/services/repository_provider.dart';
import 'package:localsync/services/theme_service.dart';

void main() {
  late Directory vault;

  setUp(() {
    vault = Directory.systemTemp.createTempSync('ls_folder_card_');
    const repo = Repository(
      id: 1,
      name: 'Obsidian_vault',
      remoteHost: '172.20.10.11',
      remoteUser: 'rapi5',
      remotePath: '/home/rapi5/Documents/Git/vault.git',
      localPath: '/tmp/vault',
      vaultBookmark: 'bookmark',
      obsidianVaultPath: '/tmp/vault',
    );
    SharedPreferences.setMockInitialValues(
        {'db_repositories': jsonEncode([repo.toMap()])});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall call) async => '/tmp');
    messenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity'),
        (MethodCall call) async => ['none']);
    messenger.setMockMethodCallHandler(
        const MethodChannel('localsync/vault_folder'), (MethodCall call) async {
      if (call.method == 'startAccessing') return {'path': vault.path};
      return null;
    });
  });

  tearDown(() => vault.deleteSync(recursive: true));

  testWidgets('LOCALSYNC FOLDER card', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final ctrl = LinkingController(
        desktopUser: 'rapi5', desktopIp: '172.20.10.11', bareRepoPath: '');
    final repoProvider = RepositoryProvider();

    await tester.runAsync(() async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: ctrl),
          ChangeNotifierProvider.value(value: repoProvider),
          ChangeNotifierProvider.value(value: ThemeService()),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    final card = find.text('LOCALSYNC FOLDER');
    await tester.scrollUntilVisible(card, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pump();
    expect(find.text('LocalSync'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'LocalSync'), 'Projects/LocalSync');
    await tester.pump();
    Scrollable.ensureVisible(tester.element(card), alignment: 0.05);
    // Settings has looping sparkle animations - pumpAndSettle never
    // settles, so a fixed pump instead.
    await tester.pump(const Duration(milliseconds: 500));
    tester.takeException();

    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/localsync_folder_card_preview.png'));
  });
}
