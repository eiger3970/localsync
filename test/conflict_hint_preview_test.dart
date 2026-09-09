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

  testWidgets(
      'shows the contains-everything hint when one side is a superset of the other',
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
    // Deliberately constructed, not sourced from a real note - unlike
    // the leading-time hint above, "one side contains the other" is a
    // general string property, not something specific to real journal
    // content, so a clearly-labeled synthetic example is honest here
    // rather than implying this exact text came from a live file.
    const entry = ConflictEntry(
      filePath: 'Journal/2026/09/example.md',
      versions: [
        ConflictVersion(
            who: 'yours', body: 'Fixed the pairing screen this morning.'),
        ConflictVersion(
            who: 'desktop obsidian',
            when: '202609081200',
            body: 'Fixed the pairing screen this morning. Also pushed '
                'the follow-up fix.'),
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

    expect(find.textContaining('these look like two separate entries'),
        findsNothing);
    expect(
        find.textContaining('already contains all of the other'),
        findsOneWidget);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/conflict_hint_contains_preview.png'),
    );
  });

  testWidgets('shows a warning when one side is suspiciously short',
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
    // Constructed example - one side genuinely tiny next to a
    // substantial other side, the shape this warning exists for.
    const entry = ConflictEntry(
      filePath: 'Journal/2026/09/example.md',
      versions: [
        ConflictVersion(who: 'yours', body: 'ok'),
        ConflictVersion(
            who: 'desktop obsidian',
            when: '202609081200',
            body: 'Fixed the pairing screen this morning after a long '
                'chase through every log file on the desktop side.'),
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

    expect(find.textContaining('these look like two separate entries'),
        findsNothing);
    expect(find.textContaining('already contains all of the other'),
        findsNothing);
    expect(
        find.textContaining('much shorter than the other'), findsOneWidget);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/conflict_hint_short_preview.png'),
    );
  });

  testWidgets(
      'names both sides when only one duplicates, without telling the user which to keep',
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
    // Same shape as the real Sep 7th conflict this session hit - the
    // same reminder paragraph pasted twice into "yours."
    const entry = ConflictEntry(
      filePath: 'Journal/2026/09/example.md',
      versions: [
        ConflictVersion(
            who: 'yours',
            body: '# Tonight\n\n'
                '1. Hand him your phone and open the CV generator.\n\n'
                '# Tonight\n\n'
                '1. Hand him your phone and open the CV generator.'),
        ConflictVersion(
            who: 'desktop obsidian',
            when: '202609081200',
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

    // 2026-09-08, corrected same day - real feedback, live: "so this
    // example needs both kept. Tapping right would keep the right and
    // wipe the left which is wrong, right?" An earlier version of this
    // hint told the user to tap the clean side instead - genuinely
    // wrong here, since "yours" (the duplicated side) has real content
    // ("desktop" doesn't) that has nothing to do with the other side's
    // topic at all. The hint now only states the fact (which side, and
    // that the other one doesn't share the problem) and leaves the
    // actual keep/discard judgment to the user - it has no way to know
    // whether the two sides are the same topic or not.
    //
    // 2026-09-08, later same day - real feedback, live: "how does merge
    // delete the duplicate and keep the 1 copy and then add the right?,
    // does that realy work?" Verified via a throwaway test calling
    // mergeHunks() directly: when the two sides share zero common
    // content (this fixture's shape - a duplicated CV reminder vs. an
    // unrelated diary line), mergeHunks collapses to exactly one hunk,
    // so Merge behaves identically to picking a whole side here - it
    // does NOT let you keep one copy of the duplicate plus the other
    // side. The hint's wording now branches on that (mergeWouldHelp)
    // instead of always pointing at "Merge text instead".
    expect(
        find.textContaining(
            '"This device" (left) repeats the same paragraph twice - '
            '"desktop obsidian - 202609081200" doesn\'t have that '
            'problem. The two sides share nothing in common, so '
            'neither "Keep both" nor "Merge" can drop just the '
            'duplicate - picking a whole side, or Keep Both plus a '
            'manual cleanup after, are the real options.'),
        findsOneWidget);
    expect(find.textContaining('"Merge text instead" below can'),
        findsNothing);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/conflict_hint_duplicate_preview.png'),
    );
  });

  testWidgets(
      'points at Merge when the sides share enough content for it to actually help',
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
    // Constructed so the two sides share a middle paragraph (verified
    // separately via mergeHunks() to actually split into multiple
    // hunks), unlike the fixture above where the sides share nothing -
    // this is the case where pointing at "Merge text instead" is
    // actually true.
    const entry = ConflictEntry(
      filePath: 'Journal/2026/09/example2.md',
      versions: [
        ConflictVersion(
            who: 'yours',
            body: 'First paragraph only on this device.\n\n'
                'This paragraph is identical on both sides.\n\n'
                'First paragraph only on this device.'),
        ConflictVersion(
            who: 'desktop obsidian',
            when: '202609081200',
            body: 'This paragraph is identical on both sides.\n\n'
                'Desktop-only closing paragraph.'),
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
        find.textContaining('"Merge text instead" below can keep one '
            'copy plus everything from the other side.'),
        findsOneWidget);
    expect(find.textContaining('share nothing in common'), findsNothing);
  });

  testWidgets(
      'falls back to the neutral wording when both sides duplicate - nothing to recommend',
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
    // Constructed - both sides genuinely have a repeated paragraph, so
    // there's no clean side left to recommend.
    const entry = ConflictEntry(
      filePath: 'Journal/2026/09/example.md',
      versions: [
        ConflictVersion(
            who: 'yours',
            body: 'First real paragraph of real length here.\n\n'
                'First real paragraph of real length here.'),
        ConflictVersion(
            who: 'desktop obsidian',
            when: '202609081200',
            body: 'A different real paragraph of real length.\n\n'
                'A different real paragraph of real length.'),
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

    expect(find.textContaining('worth cleaning up after you resolve this'),
        findsOneWidget);
    expect(find.textContaining('instead'), findsNothing);
  });
}
