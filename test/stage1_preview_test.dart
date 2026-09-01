// Local visual verification only - not part of the real suite's
// regression coverage. Renders the real Stage 1 (unpaired) screen to a
// PNG so the layout can actually be checked before pushing/sideloading,
// instead of guessing pixel values blind. Run with:
//   flutter test test/stage1_preview_test.dart --update-goldens
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:localsync/features/linking/linking_controller.dart';
import 'package:localsync/screens/linking_screen.dart';
import 'package:localsync/services/repository_provider.dart';
import 'package:localsync/services/purchase_service.dart';

void main() {
  setUp(() {
    // Desktop settings pre-filled (matches this test's real intent: an
    // already-configured user re-confirming pairing, not a first-timer -
    // an empty-settings user correctly gets redirected to SettingsScreen
    // by the deliberate 2026-08-30 fix in _onKeyPairingSettled, which
    // isn't what this test is checking).
    SharedPreferences.setMockInitialValues({
      'db_desktop_user': 'rapi5',
      'db_desktop_ip': '172.20.10.11',
      'db_bare_repo_path':
          '/home/rapi5/Documents/Git/pi5-obsidian/Git_bare_repo/Md_files_bare.git',
    });
    // Same gap as appbar_preview_test.dart: something in this screen's
    // init touches path_provider (real plugin, no test-env
    // implementation) - irrelevant to this visual capture, just needs to
    // not throw.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (MethodCall call) async => '/tmp');
  });

  testWidgets('capture real Stage 1 screen', (tester) async {
    // iPhone 13/14-ish logical size.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final ctrl = LinkingController(
      desktopUser: 'rapi5',
      desktopIp: '172.20.10.11',
      bareRepoPath: '/home/rapi5/Documents/Git/pi5-obsidian/Git_bare_repo/Md_files_bare.git',
      sshPort: 22,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: ctrl),
          ChangeNotifierProvider(create: (_) => RepositoryProvider()),
          // 2026-09-01: added alongside PkmSyncUpsell landing on the
          // file-sync-setup screen (linking_screen.dart) - unconfigured
          // (no init() call) is deliberate and safe, same as
          // PurchaseService's own real fallback: getOfferings()
          // returns null without throwing, which PkmSyncUpsell already
          // renders as its quiet "coming soon" state.
          Provider<PurchaseService>.value(value: PurchaseService()),
        ],
        child: const MaterialApp(home: LinkingScreen()),
      ),
    );
    // Not pumpAndSettle - the key's pulse animation repeats forever by
    // design, so it never settles. A few fixed pumps is enough for
    // layout/paint to land. The horizontal-overflow exception below is
    // the test environment's fallback font being wider than any real
    // device font this screen has actually shipped with - swallowed,
    // not a real bug.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    tester.takeException();

    final pairDeviceBottom = tester.getBottomLeft(find.text('1. PAIR YOUR DEVICE')).dy;
    // Two matches now that Stage 2/3's real content is always in the
    // tree (this file's own lockCaption in the canvas, plus another
    // desktopUser@desktopIp mention further down in Stage 2/3) - the
    // canvas caption is the first one painted.
    final lockCaptionRect = tester.getRect(find.text('rapi5@172.20.10.11').first);
    final step2Top = tester.getTopLeft(find.text('2. DESKTOP PASSWORD')).dy;
    // ignore: avoid_print
    print('CANVAS_MEASUREMENTS: '
        'pairDeviceBottom=$pairDeviceBottom '
        'lockCaptionBottom=${lockCaptionRect.bottom} '
        'step2Top=$step2Top '
        'gap_after_content=${lockCaptionRect.bottom - pairDeviceBottom} '
        'gap_before_step2=${step2Top - lockCaptionRect.bottom}');

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/stage1_preview.png'),
    );
  });

  testWidgets('drag gesture still pairs - real risk given Stage 2/3 now share a Column with the canvas', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final ctrl = LinkingController(
      desktopUser: 'rapi5',
      desktopIp: '172.20.10.11',
      bareRepoPath: '/home/rapi5/Documents/Git/pi5-obsidian/Git_bare_repo/Md_files_bare.git',
      sshPort: 22,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: ctrl),
          ChangeNotifierProvider(create: (_) => RepositoryProvider()),
          // 2026-09-01: added alongside PkmSyncUpsell landing on the
          // file-sync-setup screen (linking_screen.dart) - unconfigured
          // (no init() call) is deliberate and safe, same as
          // PurchaseService's own real fallback: getOfferings()
          // returns null without throwing, which PkmSyncUpsell already
          // renders as its quiet "coming soon" state.
          Provider<PurchaseService>.value(value: PurchaseService()),
        ],
        child: const MaterialApp(home: LinkingScreen()),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    tester.takeException();

    // Sanity check: Stage 1's content is actually present pre-drag.
    expect(find.text('1. PAIR YOUR DEVICE'), findsOneWidget);

    final keyCenter = tester.getCenter(find.byKey(const ValueKey('key')));
    final lockCenter = tester.getCenter(find.byKey(const ValueKey('lock')));
    // ignore: avoid_print
    print('DRAG_POSITIONS: keyCenter=$keyCenter lockCenter=$lockCenter');

    // dragSurface owns onPanStart/onPanUpdate/onPanEnd (not a
    // Draggable/DragTarget). Manual gesture with several intermediate
    // moves, checking the key's on-screen position mid-drag - if the
    // gesture never reaches dragSurface (the exact failure mode round 11
    // fixed), the key simply won't move at all, which tells this apart
    // from "moved but target math missed."
    final gesture = await tester.startGesture(keyCenter);
    await tester.pump(const Duration(milliseconds: 20));
    final delta = lockCenter - keyCenter;
    for (var i = 1; i <= 10; i++) {
      await gesture.moveBy(delta / 10);
      await tester.pump(const Duration(milliseconds: 20));
    }
    final keyMidDrag = tester.getCenter(find.byKey(const ValueKey('key')));
    // ignore: avoid_print
    print('DRAG_POSITIONS: keyMidDrag=$keyMidDrag (started at $keyCenter, '
        'moved=${keyMidDrag != keyCenter})');
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 50));
    // onSettled fires after the settle animation, not instantly on
    // release - pump well past minRun (Duration.zero here) and any
    // snap/settle animation.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    tester.takeException();

    // 2026-08-25, follow-up - "it changes page to 2 and 3. I want the
    // user to simply flow down the same screen." Stage 1's content used
    // to drop out of the tree once paired (checked here as findsNothing)
    // - that vanishing was itself what read as a page swap. Now it
    // should stay mounted (the key visually snapped in the lock reads
    // as "done"), with Steps 2/3 appearing below it instead of
    // replacing it.
    expect(find.text('1. PAIR YOUR DEVICE'), findsOneWidget);
    expect(find.text('2. DESKTOP PASSWORD'), findsOneWidget);
    expect(find.text('3. SET UP VAULT'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/stage2_after_pairing.png'),
    );
  });
}
