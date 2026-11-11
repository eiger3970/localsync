// Local visual check only: the one-line "Resolved" banner and the pulsing PUSH zone.
//   flutter test test/push_glow_preview_test.dart --tags preview --run-skipped --update-goldens
@Tags(['preview'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/theme.dart';
import 'package:localsync/widgets/gif_swipe_trigger.dart';

void main() {
  testWidgets('banner + glowing PUSH', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    Widget screen(bool glow) => MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            backgroundColor: kVoid,
            body: Column(children: [
              MaterialBanner(
                backgroundColor: kSurface,
                content: Text.rich(TextSpan(style: TextStyle(color: kStar, fontSize: 15), children: [
                  WidgetSpan(alignment: PlaceholderAlignment.middle, child: Icon(Icons.check_circle, color: kGreen, size: 16)),
                  const TextSpan(text: ' Resolved  '),
                                    WidgetSpan(alignment: PlaceholderAlignment.middle, child: Icon(Icons.upload_rounded, color: kStar, size: 16)),
                  const TextSpan(text: ' PUSH  '),
                  const TextSpan(text: ' '),
                  TextSpan(text: 'Backup', style: TextStyle(color: kGreen, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
                ])),
                actions: [TextButton(onPressed: () {}, child: Text('DISMISS', style: TextStyle(color: kGreen)))],
              ),
              const Spacer(),
              Expanded(
                child: GifSwipeTrigger(
                  assetPath: 'assets/gifs/git_push.gif',
                  caption: 'PUSH',
                  glowing: glow,
                  swipeDown: false,
                  gifHeight: 198,
                  onConfirm: () async {},
                ),
              ),
            ]),
          ),
        );
    await tester.pumpWidget(screen(true));
    await tester.pump(const Duration(milliseconds: 1100)); // brightest
    tester.takeException();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/push_glow_bright.png'));
    await tester.pump(const Duration(milliseconds: 1100)); // dimmest
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/push_glow_dim.png'));
    await tester.pumpWidget(screen(false));
    await tester.pump();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/push_glow_off.png'));
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
