import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/theme.dart';
import 'package:localsync/widgets/flag_backdrop.dart';

// 2026-08-22: same reasoning as flag_frame_all_skins_test.dart - this
// app has real prior history of skin/asset code breaking invisibly
// with no way to preview before a sideload. FlagBackdrop is newer,
// more complex code (tiling loop, rotation, saveLayer group alpha)
// than the border painter, so it gets the same per-palette sweep.
void main() {
  tearDown(() => AppTheme.set(terminalGreenPalette));

  for (final palette in allPalettes) {
    testWidgets('FlagBackdrop paints ${palette.id} without throwing', (tester) async {
      AppTheme.set(palette);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FlagBackdrop(child: SizedBox(width: 300, height: 600)),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
