// Local visual verification only - checks the "Keep both versions?"
// confirm dialog actually renders/fits after adding the new Undo
// point, without a full device build. Run with:
//   flutter test test/keep_both_dialog_preview_test.dart --update-goldens
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

  testWidgets('Keep both confirm dialog renders with the new Undo point',
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

    await tester.tap(find.text('KEEP BOTH'));
    await tester.pumpAndSettle();
    tester.takeException();

    // Real check, not just a screenshot: every dialog point must
    // actually be on screen, not clipped/overflowing off it.
    expect(find.text('Keep both versions?'), findsOneWidget);
    expect(find.text('Keeps both versions, as plain text'), findsOneWidget);
    expect(
        find.text(
            'An UNDO button appears right after, on the confirmation message'),
        findsOneWidget);
    expect(find.byIcon(Icons.undo), findsOneWidget);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/keep_both_dialog_preview.png'),
    );
  });
}
