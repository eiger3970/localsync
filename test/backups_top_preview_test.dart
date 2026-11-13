// Local visual preview only (2026-11-13): Backups screen, total + Delete all at the top.
//   flutter test test/backups_top_preview_test.dart --update-goldens
@Tags(['preview'])
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:localsync/models/repository.dart';
import 'package:localsync/screens/backups_screen.dart';
import 'package:localsync/services/localsync_cleanup.dart';
import 'package:localsync/theme.dart';

Future<void> _icons() async {
  final f = File('/home/rapi5/snap/flutter/common/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())))).load();
  for (final e in {'Roboto': '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', '.SF UI Text': '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'}.entries) {
    await (FontLoader(e.key)..addFont(Future.value(ByteData.sublistView(File(e.value).readAsBytesSync())))).load();
  }
}

void main() {
  testWidgets('backups top', (tester) async {
    await tester.runAsync(_icons);
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final folders = [
      for (var d = 13; d >= 1; d--)
        BackupFolder('.localsync_backups/Backup 202611${d.toString().padLeft(2, '0')}0944', 3950, 51 << 20),
    ];
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: BackupsScreen(
          repo: const Repository(name: 'Vault', remoteHost: '', remoteUser: '', remotePath: '', localPath: '', obsidianVaultPath: ''),
          previewFolders: folders),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    while (tester.takeException() != null) {}
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/backups_top.png'));
  });
}
