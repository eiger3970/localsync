// Local visual check only: the three states of the "Conflict fixed" banner (replica of the real layout).
//   flutter test test/resolved_banner_preview_test.dart --tags preview --run-skipped --update-goldens
@Tags(['preview'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/theme.dart';

Widget banner(IconData icon, Color c, String line2) => MaterialBanner(
      backgroundColor: kSurface,
      content: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text.rich(TextSpan(style: TextStyle(color: kStar, fontSize: 15), children: [
          WidgetSpan(alignment: PlaceholderAlignment.middle, child: Icon(Icons.check_circle, color: kGreen, size: 16)),
          const TextSpan(text: ' Conflict fixed  '),
          TextSpan(text: 'Backup', style: TextStyle(color: kGreen, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
        ])),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: [
            Icon(icon, color: c, size: 16),
            const SizedBox(width: 6),
            Flexible(child: Text(line2, style: TextStyle(color: kStar, fontSize: 15))),
          ]),
        ),
      ]),
      actions: [TextButton(onPressed: () {}, child: Text('DISMISS', style: TextStyle(color: kTextDim)))],
    );

void main() {
  testWidgets('banner states', (tester) async {
    tester.view.physicalSize = const Size(1170, 900);
    tester.view.devicePixelRatio = 3.0;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        backgroundColor: kVoid,
        body: Column(children: [
          banner(Icons.upload_rounded, kGreen, 'Swipe up on PUSH'),
          const SizedBox(height: 16),
          banner(Icons.sync, kStar, 'Pushed. Updating desktop...'),
          const SizedBox(height: 16),
          banner(Icons.check_circle, kGreen, 'Desktop updated. Old text in Obsidian? Reopen the note'),
          const SizedBox(height: 16),
          banner(Icons.schedule, kStar, 'Pushed. Desktop updates itself within 5min'),
        ]),
      ),
    ));
    await tester.pump();
    tester.takeException();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/resolved_banner_states.png'));
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
