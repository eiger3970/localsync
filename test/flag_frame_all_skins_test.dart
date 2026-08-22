import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/theme.dart';
import 'package:localsync/widgets/flag_frame.dart';

// 2026-08-22: this app has real prior history of skins/assets breaking
// invisibly with no way to preview before a sideload (see
// flag_frame.dart's header). One CustomPainter now serves 6 different
// FlagKind treatments across 22 palettes with per-flag data
// (stripeWeights, southernCrossRedStars, etc.) - a bad combination
// (e.g. an empty flagStripes list reaching FlagKind.stripes) would
// throw only for that one skin, easy to miss by hand-testing just
// whichever skin is currently selected.
void main() {
  tearDown(() => AppTheme.set(terminalGreenPalette));

  for (final palette in allPalettes) {
    testWidgets('FlagFrame paints ${palette.id} without throwing', (tester) async {
      AppTheme.set(palette);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FlagFrame(child: SizedBox(width: 300, height: 600)),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
