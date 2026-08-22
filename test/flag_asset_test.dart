import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/theme.dart';

// 2026-08-22: this app has real prior history of SVG assets breaking
// invisibly with no way to preview before a sideload (see
// flag_frame.dart's header). This test is the actual guard: every
// palette that declares a flagAsset must be a real registered asset
// that SvgPicture can load without throwing, not just a string that
// happens to compile.
void main() {
  final withAssets = allPalettes.where((p) => p.flagAsset != null);

  testWidgets('every palette.flagAsset loads without throwing', (tester) async {
    for (final palette in withAssets) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 64,
              height: 24,
              child: SvgPicture.asset(palette.flagAsset!, fit: BoxFit.cover),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: palette.id);
    }
  });

  test('at least one palette has sourced a real flag asset', () {
    expect(withAssets, isNotEmpty);
  });
}
