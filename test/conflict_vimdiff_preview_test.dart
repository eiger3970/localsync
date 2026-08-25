// Local visual verification only - renders the redesigned side-by-side
// conflict picker with realistic text so the vimdiff-style layout can
// actually be checked before pushing/sideloading.
//   flutter test test/conflict_vimdiff_preview_test.dart --update-goldens
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:localsync/models/repository.dart';
import 'package:localsync/screens/conflict_picker_screen.dart';
import 'package:localsync/services/conflict_scanner.dart';

void main() {
  testWidgets('capture side-by-side conflict diff, portrait and landscape',
      (tester) async {
    // ConflictPickerScreen reads the saved device name via
    // DatabaseService/shared_preferences on initState - unmocked in a
    // widget test, that's a real platform channel with nothing behind
    // it in the test environment.
    SharedPreferences.setMockInitialValues({});
    final entry = ConflictEntry(
      filePath: 'Journal/2026/08/Aug 24th, 2026.md',
      isKanban: false,
      matchStart: 0,
      matchEnd: 0,
      versions: [
        const ConflictVersion(
          who: 'This device',
          body: 'Spent the morning fixing the LocalSync pairing screen. '
              'The drag gesture kept losing to the scroll view, took '
              'several rounds to track down. Called the bank about the '
              'account in the afternoon, no progress.',
        ),
        const ConflictVersion(
          who: 'desktop obsidian',
          when: '202608251230',
          body: 'Spent the morning testing LocalSync on the real device. '
              'The drag gesture kept losing to the scroll view, took '
              'several rounds to track down. Emailed Denis Martin about '
              'the domicile case in the afternoon, waiting on a reply.',
        ),
      ],
    );
    final repo = Repository(
      id: 1,
      name: 'Obsidian_vault',
      remoteHost: '172.20.10.11',
      remoteUser: 'rapi5',
      remotePath: '/stub/Md_files_bare.git',
      localPath: '/stub/vault',
      obsidianVaultPath: 'On My iPhone/Obsidian/Obsidian_vault',
      vaultBookmark: 'stub',
    );

    for (final (label, size) in [
      ('portrait', const Size(1170, 2532)),
      ('landscape', const Size(2532, 1170)),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 3.0;
      await tester.pumpWidget(MaterialApp(
        home: ConflictPickerScreen(repo: repo, entry: entry),
      ));
      await tester.pump(const Duration(milliseconds: 200));
      tester.takeException();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/conflict_vimdiff_$label.png'),
      );
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
