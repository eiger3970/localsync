// Local visual preview only (2026-10-13): the install Settings page - owner:
// "overdone ... repeated about 4 times". Real icon font loaded so icons show.
//   flutter test test/settings_install_clean_preview_test.dart --update-goldens
@Tags(['preview'])
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:localsync/features/linking/linking_controller.dart';
import 'package:localsync/screens/settings_screen.dart';
import 'package:localsync/screens/linking_screen.dart';
import 'package:localsync/services/repository_provider.dart';
import 'package:localsync/services/theme_service.dart';
import 'package:localsync/theme.dart';

Future<void> _icons() async {
  final f = File('/home/rapi5/snap/flutter/common/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  final l = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  await l.load();
  for (final e in {'monospace': '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf', 'Roboto': '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', '.SF UI Text': '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'}.entries) {
    final g = FontLoader(e.key)..addFont(Future.value(ByteData.sublistView(File(e.value).readAsBytesSync())));
    await g.load();
  }
}

Future<void> _render(WidgetTester tester, bool pairing, String golden, double h, {Widget? page}) async {
  await tester.runAsync(_icons);
  SharedPreferences.setMockInitialValues({});
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (c) async => '/tmp');
  m.setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/connectivity'), (c) async => ['none']);
  tester.view.physicalSize = Size(1170, h);
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
    child: MaterialApp(theme: buildAppTheme(), builder: (c, child) => ColoredBox(color: const Color(0xFF03020A), child: child), home: page ?? SettingsScreen(neededForPairing: pairing)),
  ));
  await tester.pump(const Duration(milliseconds: 700));
  while (tester.takeException() != null) {}
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(golden));
}

void main() {
  const tag = String.fromEnvironment('TAG', defaultValue: 'after');
  testWidgets('install Settings, from setup', (t) => _render(t, true, 'goldens/settings_install_pairing_$tag.png', 3600));
  testWidgets('install page', (t) => _render(t, true, 'goldens/install_page_$tag.png', 2532, page: const LinkingScreen()));
  testWidgets('install Settings, from menu', (t) => _render(t, false, 'goldens/settings_install_menu_$tag.png', 3600));
}
