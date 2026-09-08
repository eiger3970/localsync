// Local visual verification only - checks the new "these look like
// two separate entries" hint actually renders on screen when both
// sides start with a clock time (and stays absent otherwise - see
// keep_both_dialog_preview_test.dart's fixture, which has no leading
// time on one side and must NOT show this hint). Run with:
//   flutter test test/conflict_hint_preview_test.dart --update-goldens
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

  testWidgets('shows the separate-entries hint when both sides have a leading time',
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
    // Real 2026-08-28 shape - both sides genuinely start with a bare
    // HHMM time, exactly the case the hint exists for.
    const entry = ConflictEntry(
      filePath: 'Journal/2026/08/Aug 28th, 2026.md',
      versions: [
        ConflictVersion(
            who: 'yours',
            body: '2105 salad Caucasian Swiss? Gave me a hard time.'),
        ConflictVersion(
            who: 'desktop obsidian',
            when: '202609041645',
            body: '0715 Clothes washed last night are 80% damp wet.'),
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

    expect(
        find.textContaining('these look like two separate entries'),
        findsOneWidget);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/conflict_hint_preview.png'),
    );
  });
}
