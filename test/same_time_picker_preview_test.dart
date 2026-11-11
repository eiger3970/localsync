@Tags(['preview'])
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:localsync/models/repository.dart';
import 'package:localsync/screens/conflict_picker_screen.dart';
import 'package:localsync/services/conflict_scanner.dart';

const note = '0803 backpack missing selfie stick, toothpaste and electric toothbrush.\n\n'
    'I left back pack in 31C and spoke with Anilban until 2230.\nI brushed my teeth, put in top of backpack.\nBetween bed and library, stuff is missing.\n\n'
    '0803 unpacking backpack and the selfie stick, toothpaste and electric toothbrush have been stolen.\n\n'
    '1400 I collected 2 letters from Riponne.\n\n2030 old thug pushed in.\n';

void main() {
  testWidgets('same-time picker', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final real = File('/tmp/claude-1000/-home-rapi5/7dffc7a1-ae8b-450d-baf5-2b6e3fdfb64b/scratchpad/nov10_real.md').readAsStringSync();
    final entries = sameTimeEntries('Journal/2026/11/Nov 10th, 2026.md', real, {});
    // ignore: avoid_print
    print('ENTRIES: ${entries.length}');
    final entry = entries.single;
    final repo = Repository(
      id: 1, name: 'Obsidian_vault', remoteHost: '172.20.10.11', remoteUser: 'rapi5',
      remotePath: '/stub/Md_files_bare.git', localPath: '/stub/vault',
      obsidianVaultPath: 'On My iPhone/Obsidian/Obsidian_vault', vaultBookmark: 'stub');
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    await tester.pumpWidget(MaterialApp(home: ConflictPickerScreen(repo: repo, entry: entry)));
    await tester.pump(const Duration(milliseconds: 300));
    var ex = tester.takeException();
    // ignore: avoid_print
    print('EXCEPTION portrait: $ex');
    tester.view.physicalSize = const Size(2532, 1170);
    await tester.pump(const Duration(milliseconds: 300));
    ex = tester.takeException();
    // ignore: avoid_print
    print('EXCEPTION landscape: $ex');
    tester.view.physicalSize = const Size(1170, 2532);
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/same_time_picker.png'));
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
