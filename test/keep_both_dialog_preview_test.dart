// Local visual verification only - checks the "Keep both versions?"
// confirm dialog AND the (i) info popup render the exact same points
// in the exact same order (they drifted apart across earlier edits -
// this is what catches that class of bug before a build). Run with:
//   flutter test test/keep_both_dialog_preview_test.dart --update-goldens
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:localsync/models/repository.dart';
import 'package:localsync/screens/conflict_picker_screen.dart';
import 'package:localsync/services/conflict_scanner.dart';

// The backup point renders as Text.rich (a linked suffix), not plain
// Text.data - find.text() only matches .data, so a predicate reading
// either shape is needed to check ALL five points uniformly.
Finder findPointContaining(String substring) => find.byWidgetPredicate((w) {
      if (w is! Text) return false;
      final plain = w.data ?? w.textSpan?.toPlainText() ?? '';
      return plain.contains(substring);
    });

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (MethodCall call) async => '/tmp');
  });

  testWidgets('Keep both confirm dialog and info popup match exactly',
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

    // Canonical order, both dialogs must match this exactly.
    const confirmOrder = [
      'UNDO button appears right after, on the confirmation message',
      'Backs up all versions first',
      'Text sorted by time, if both texts start with a clock time - otherwise left as is',
      'Text versions of both kept, as plain text',
      'Text visible, all kept as plain text paragraphs, nothing hidden',
    ];

    void checkOrder(String label) {
      var lastY = -1.0;
      for (final t in confirmOrder) {
        final finder = findPointContaining(t);
        expect(finder, findsOneWidget, reason: '$label missing: $t');
        final y = tester.getTopLeft(finder).dy;
        expect(y, greaterThan(lastY), reason: '$label: "$t" out of order');
        lastY = y;
      }
    }

    await tester.tap(find.text('KEEP BOTH'));
    await tester.pumpAndSettle();
    tester.takeException();
    expect(find.text('Keep both versions?'), findsOneWidget);
    checkOrder('confirm dialog');
    // Real check this test exists to catch: no cloud-shaped icon
    // anywhere in a privacy/local-only app's own dialog.
    expect(find.byIcon(Icons.backup), findsNothing);
    expect(find.byIcon(Icons.cloud), findsNothing);
    expect(find.byIcon(Icons.done_all), findsOneWidget);
    expect(find.byIcon(Icons.library_add_check), findsOneWidget);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/keep_both_dialog_preview.png'),
    );

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    // Two (i) buttons exist on this screen (MERGE PIECES INSTEAD has
    // its own, above this one) - KEEP BOTH's is the one lower on
    // screen / later in source order.
    await tester.tap(find.byIcon(Icons.info_outline).last);
    await tester.pumpAndSettle();
    tester.takeException();
    checkOrder('info popup');

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/keep_both_info_preview.png'),
    );
  });
}
