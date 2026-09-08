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
    // 2026-09-08: real content, verbatim from the actual real Aug 29th
    // conflict this session's user confirmed the hint on-device for -
    // an earlier version of this test used fabricated/borrowed text
    // that happened to also satisfy allHaveLeadingTime, which masked
    // that the real Aug 28th conflict (checked separately) does NOT
    // qualify (one side has no leading time at all). Using real,
    // verified text here so this test can never drift from reality
    // the same way again.
    const entry = ConflictEntry(
      filePath: 'Journal/2026/08/Aug 29th, 2026.md',
      versions: [
        ConflictVersion(
            who: 'yours',
            body: '0823 tough Caucasian guy walked past with stinky eye. '
                'So I quietly said smoking is dangerous and bad for your '
                'health.'),
        ConflictVersion(
            who: 'desktop obsidian',
            when: '202609041645',
            body: '0715 I left my bed 32A with my phone, but left '
                'earphone on bed, for the 3rd floor toilet.'),
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
