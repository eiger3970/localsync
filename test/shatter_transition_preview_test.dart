// Local visual verification only - frames of the welcome -> app glass
// transition (shatter_page_route.dart) at a few points in time. Run with:
//   flutter test test/shatter_transition_preview_test.dart --update-goldens
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/widgets/shatter_page_route.dart';

void main() {
  testWidgets('glass transition frames', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      home: const Scaffold(backgroundColor: Color(0xFFF3FBFA)),
    ));
    nav.currentState!.push(ShatterPageRoute(
        builder: (_) => const Scaffold(backgroundColor: Colors.black)));
    await tester.pump();
    var elapsed = 0;
    for (final ms in [100, 250, 420, 800, 1150]) {
      await tester.pump(Duration(milliseconds: ms - elapsed));
      elapsed = ms;
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('goldens/shatter_$ms.png'));
    }
    await tester.pumpAndSettle();
  });
}
