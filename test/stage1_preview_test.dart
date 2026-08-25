// Local visual verification only - not part of the real suite's
// regression coverage. Renders the real Stage 1 (unpaired) screen to a
// PNG so the layout can actually be checked before pushing/sideloading,
// instead of guessing pixel values blind. Run with:
//   flutter test test/stage1_preview_test.dart --update-goldens
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:localsync/features/linking/linking_controller.dart';
import 'package:localsync/screens/linking_screen.dart';

void main() {
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
      ChangeNotifierProvider.value(
        value: ctrl,
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
      ChangeNotifierProvider.value(
        value: ctrl,
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

    // Real assertion: onSettled -> setState(_paired = true) -> Stage 1's
    // content (stage1Widgets) drops out of the tree entirely. If the
    // gesture got eaten by a scroll ancestor (the exact bug round 11
    // fixed), this stays present forever instead.
    expect(find.text('1. PAIR YOUR DEVICE'), findsNothing);
  });
}
