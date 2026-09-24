// Local visual verification only - the 2026-09-24 first-setup safety
// prompts (linking_screen.dart): wrong-folder, backup-first, and the
// after-setup reminder. Run with:
//   flutter test test/vault_folder_prompts_preview_test.dart --update-goldens
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/features/linking/linking_controller.dart';
import 'package:localsync/screens/linking_screen.dart';
import 'package:localsync/theme.dart';

Future<void> _show(WidgetTester tester, VaultFolderCheck check, String golden) async {
  late BuildContext ctx;
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      backgroundColor: kVoid,
      body: Builder(builder: (c) {
        ctx = c;
        return const SizedBox.expand();
      }),
    ),
  ));
  confirmVaultFolder(ctx, check);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(golden));
}

void main() {
  setUp(() {});
  testWidgets('wrong folder', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await _show(
        tester,
        const VaultFolderCheck(
            absolutePath: '/private/var/mobile/Containers/Data/Application/A/Documents',
            folderName: 'Obsidian',
            isEmpty: false,
            isVault: false,
            childVaults: ['LocalSync Test', 'Obsidian_phone_vault'],
            backupFolder: 'LocalSync'),
        'goldens/prompt_wrong_folder.png');
  });
  testWidgets('backup first', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await _show(
        tester,
        const VaultFolderCheck(
            absolutePath: '/private/var/mobile/Containers/Data/Application/A/Documents/Obsidian_phone_vault',
            folderName: 'Obsidian_phone_vault',
            isEmpty: false,
            isVault: true,
            childVaults: [],
            backupFolder: 'LocalSync'),
        'goldens/prompt_backup_first.png');
  });
  testWidgets('no vault yet', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await _show(
        tester,
        const VaultFolderCheck(
            absolutePath: '/private/var/mobile/Containers/Data/Application/A/Documents',
            folderName: 'Documents',
            isEmpty: true,
            isVault: false,
            childVaults: [],
            backupFolder: 'LocalSync'),
        'goldens/prompt_no_vault.png');
  });
  testWidgets('reminder card', (tester) async {
    tester.view.physicalSize = const Size(390, 420);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        backgroundColor: kVoid,
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: BackupReminderCard(
              backupRelPath: 'LocalSync/Vault Backup 202609241415',
              vaultPath: '/private/var/mobile/Containers/Data/Application/A/Documents/Obsidian_phone_vault',
              onOpenObsidian: () async {}),
        ),
      ),
    ));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/prompt_reminder_card.png'));
  });
}
