// Local visual verification only - step ticks, "N of 4 ready" note and
// Save greyed out until 1 and 2 are valid (settings_screen.dart). Run with:
//   flutter test test/settings_ready_note_preview_test.dart --update-goldens
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:localsync/features/linking/linking_controller.dart';
import 'package:localsync/screens/settings_screen.dart';
import 'package:localsync/services/repository_provider.dart';
import 'package:localsync/services/theme_service.dart';

Future<void> _render(WidgetTester tester, String ip, String golden) async {
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
  final ctrl = LinkingController(desktopUser: 'rapi5', desktopIp: ip, bareRepoPath: '');
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
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(golden));
}

void main() {
  testWidgets('IP missing: amber note, Save greyed out', (tester) async {
    await _render(tester, '', 'goldens/settings_ready_missing_ip.png');
  });
  testWidgets('All ready: green ticks, note, Save glows', (tester) async {
    await _render(tester, '172.20.10.2', 'goldens/settings_ready_all.png');
  });
}
