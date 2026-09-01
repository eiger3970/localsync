// Local visual verification only - not part of the real suite's
// regression coverage. Just the two button types in isolation, no
// screen/provider tree around them - a direct check of the 2026-09-01
// rounded-corner theme change (theme.dart's elevatedButtonTheme and
// outlinedButtonTheme) without the placeholder-font noise a full-screen
// capture carries. Run with:
//   flutter test test/button_shapes_preview_test.dart --update-goldens
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/theme.dart';

void doNothing() {}

void main() {
  testWidgets('capture ElevatedButton and OutlinedButton corner radius',
      (tester) async {
    tester.view.physicalSize = const Size(600, 300);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(onPressed: doNothing, child: Text('CLEAR')),
                SizedBox(height: 24),
                OutlinedButton(onPressed: doNothing, child: Text('CLEAR')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/button_shapes.png'),
    );
  });
}
