// Local visual check for the WHAT HAPPENED + HOW TO FIX IT pair added
// to Stage 2's inline password-failure display - lighter than fully
// simulating the 3-stage pairing dance to reach _pairingFailure, but
// still a real render of the exact same DiagCard props/stacking.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/theme.dart';
import 'package:localsync/widgets/diag_card.dart';

void main() {
  testWidgets('WHAT HAPPENED + HOW TO FIX IT stacked, matching Stage 2\'s new pair',
      (tester) async {
    tester.view.physicalSize = const Size(1170, 1400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: kVoid,
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DiagCard(
                label: 'WHAT HAPPENED',
                text: 'Could not complete the connection to your desktop.',
                accent: Colors.redAccent,
              ),
              const SizedBox(height: 12),
              DiagCard(
                label: 'HOW TO FIX IT',
                text: '1. Re-enter your desktop password - a mistyped '
                    'password can surface as this error on some networks\n'
                    '2. Check your desktop is awake\n'
                    '3. Connect phone to desktop - hotspot or USB tether\n'
                    '4. On desktop: `sudo systemctl status ssh`\n'
                    '5. On desktop: `ip addr show` - verify IP matches '
                    'what is set in this app',
                accent: kGreen,
                icon: Icons.lightbulb_outline,
                bulleted: true,
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();
    tester.takeException();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/diag_card_pair.png'),
    );
  });
}
