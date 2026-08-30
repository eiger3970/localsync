// Local visual verification only. Renders the exact SETTINGS reminder
// SnackBar (same text/style/action as linking_screen.dart's
// _onKeyPairingSettled) to confirm the shortened message actually fits
// one line alongside the action button. Run with:
//   flutter test test/settings_snackbar_preview_test.dart --update-goldens
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('capture the real SETTINGS reminder SnackBar', (tester) async {
    tester.view.physicalSize = const Size(1170, 300);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    // Exact copy of linking_screen.dart's current text -
                    // keep in sync if that message changes again.
                    content: const Text('Desktop connection not set up yet',
                        style:
                            TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
                    backgroundColor: Colors.amber,
                    duration: const Duration(seconds: 6),
                    action: SnackBarAction(
                      label: '✨ SETTINGS',
                      textColor: Colors.black,
                      onPressed: () {},
                    ),
                  ),
                );
              },
              child: const Text('trigger'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('trigger'));
    await tester.pump(); // schedule the SnackBar
    await tester.pump(const Duration(milliseconds: 300)); // let it animate in

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/settings_snackbar_preview.png'),
    );
  });
}
