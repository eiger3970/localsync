// Local visual verification only - Backups screen with plain-words rows and
// Delete all (backups_screen.dart). Run with:
//   flutter test test/backups_screen_preview_test.dart --update-goldens
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/models/repository.dart';
import 'package:localsync/screens/backups_screen.dart';
import 'package:localsync/services/localsync_cleanup.dart';
import 'package:localsync/theme.dart';

void main() {
  testWidgets('Backups screen', (tester) async {
    tester.view.physicalSize = const Size(1170, 2000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = Repository(
        name: 'Obsidian_vault',
        remoteHost: '172.20.10.2',
        remoteUser: 'rapi5',
        remotePath: '/x.git',
        localPath: '/v',
        obsidianVaultPath: '/v');
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: BackupsScreen(repo: repo, previewFolders: const [
        BackupFolder('.localsync_backups/Backup 202609291652', 3441, 62 * 1024 * 1024, keep: true),
        BackupFolder('.localsync_backups/Conflict Backups', 425, 156 * 1024 * 1024),
        BackupFolder('.localsync_backups/Conflict Backups before 2026-09-17', 132, 48 * 1024 * 1024),
      ]),
    ));
    await tester.pump();
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/backups_screen.png'));
  });
}
