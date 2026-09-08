// Local visual verification only - checks the syncing-state app bar
// (vault name + "downloading notes" label) without a full device build.
// Run with: flutter test test/appbar_syncing_preview_test.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:localsync/models/repository.dart';
import 'package:localsync/screens/home_screen.dart';
import 'package:localsync/services/repository_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (MethodCall call) async => '/tmp');
  });

  testWidgets('name and sync-phase label share the same horizontal center',
      (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final provider = RepositoryProvider();
    await provider.addRepository(const Repository(
      name: 'Obsidian_phone_vault',
      remoteHost: '172.20.10.11',
      remoteUser: 'rapi5',
      remotePath: '/home/rapi5/Documents/Git/pi5-obsidian/Git_bare_repo/x.git',
      localPath: '',
      obsidianVaultPath: '',
      status: SyncStatus.syncing,
      syncPhase: SyncPhase.pulling,
    ));

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    tester.takeException();

    final nameRect = tester.getRect(find.text('Obsidian_phone_vault'));
    final labelRect = tester.getRect(find.text('downloading notes'));
    final nameCenter = nameRect.left + nameRect.width / 2;
    final labelCenter = labelRect.left + labelRect.width / 2;

    // ignore: avoid_print
    print('NAME rect=$nameRect center=$nameCenter');
    // ignore: avoid_print
    print('LABEL rect=$labelRect center=$labelCenter');
    // ignore: avoid_print
    print('CENTER DELTA=${(nameCenter - labelCenter).abs()}');

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/appbar_syncing_preview.png'),
    );
  });
}
