// Local visual verification only. Renders the exact SETTINGS reminder
// SnackBar (same content Row/style/action as linking_screen.dart's
// _onKeyPairingSettled) to confirm the action button stays beside the
// text instead of dropping to its own row. Run with:
//   flutter test test/settings_snackbar_preview_test.dart --update-goldens
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('capture the real SETTINGS reminder SnackBar', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
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
                    // Exact copy of linking_screen.dart's current content -
                    // keep in sync if that changes again.
                    content: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Expanded(
                          child: Text(
                            "Desktop username and IP address aren't set yet - fill them in before pairing will work.",
                            style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.black,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () {},
                          child: const Text('✨ SETTINGS',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    backgroundColor: Colors.amber,
                    duration: const Duration(seconds: 6),
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
