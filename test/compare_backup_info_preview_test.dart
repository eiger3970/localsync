// Local visual verification only - checks the new "Compare with a
// backup" info dialog (points instead of a paragraph) actually
// renders without overflow. Run with:
//   flutter test test/compare_backup_info_preview_test.dart --update-goldens
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:localsync/models/repository.dart';
import 'package:localsync/screens/conflict_picker_screen.dart';
import 'package:localsync/services/conflict_scanner.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (MethodCall call) async => '/tmp');
  });

  testWidgets('Compare with a backup info shows 3 points, no overflow',
      (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const repo = Repository(
      name: 'Obsidian_phone_vault',
      remoteHost: '172.20.10.11',
      remoteUser: 'rapi5',
      remotePath: '/home/rapi5/Documents/Git/pi5-obsidian/Git_bare_repo/x.git',
      localPath: '',
      obsidianVaultPath: '',
    );
    const entry = ConflictEntry(
      filePath: 'Journal/2026/09/Sep 7th, 2026.md',
      versions: [
        ConflictVersion(who: 'yours', body: 'Tonight\'s actions...'),
        ConflictVersion(
            who: 'desktop obsidian',
            when: '202609081010',
            body: '2105 La Soupe Populaire was quiet and calm.'),
      ],
      isKanban: false,
      matchStart: 0,
      matchEnd: 10,
    );

    await tester.pumpWidget(const MaterialApp(
      home: ConflictPickerScreen(repo: repo, entry: entry),
    ));
    await tester.pumpAndSettle();
    tester.takeException();

    // The (i) next to "Compare with a backup" - first info_outline on
    // screen, unlike the KEEP BOTH one which is last.
    await tester.tap(find.byIcon(Icons.info_outline).first);
    await tester.pumpAndSettle();
    tester.takeException();

    // "Compare with a backup" appears twice now (the link + this
    // dialog's own title) - the 3 point texts below are the real,
    // unambiguous proof the dialog opened with the right content.
    expect(find.text('Compare with a backup'), findsNWidgets(2));
    expect(
        find.text('Looks back further - every backup ever saved for '
            'this note, not just this one conflict'),
        findsOneWidget);
    expect(
        find.text('Same side-by-side diff view as above, so '
            'differences are easy to spot'),
        findsOneWidget);
    expect(
        find.text('Works anytime - even long after a conflict is '
            'already resolved'),
        findsOneWidget);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/compare_backup_info_preview.png'),
    );
  });
}
