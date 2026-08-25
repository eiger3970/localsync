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
    final lockCaptionRect = tester.getRect(find.text('rapi5@172.20.10.11'));
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
}
