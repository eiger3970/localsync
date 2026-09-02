// Local visual verification only. Reconstructs the exact _showHelp
// rendering (settings_screen.dart) for both Manual setup dialogs side by
// side, so the "make step 2 match step 3's style" change can actually be
// eyeballed before pushing, instead of just reading a diff. Run with:
//   flutter test test/manual_setup_dialogs_preview_test.dart --update-goldens
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/theme.dart';

Widget buildHelpDialog(String title, String command, List<String> points) {
  return AlertDialog(
    backgroundColor: kSurface,
    title: Text(title, style: TextStyle(color: kStar, fontSize: 16)),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.only(left: 10, top: 4, bottom: 4),
          decoration: BoxDecoration(color: kVoid, border: Border.all(color: kBorder)),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(command,
                    maxLines: 1,
                    style: TextStyle(color: kGreen, fontFamily: 'monospace', fontSize: 13)),
              ),
              Icon(Icons.copy, color: kTextMid, size: 18),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text('Command for your desktop terminal', style: TextStyle(color: kTextMid, fontSize: 12)),
        const SizedBox(height: 12),
        for (final text in points)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(text, style: TextStyle(color: kStar, fontSize: 13)),
          ),
      ],
    ),
  );
}

void main() {
  testWidgets('capture step-2 and step-3 Manual setup dialogs side by side', (tester) async {
    tester.view.physicalSize = const Size(1170, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        backgroundColor: kVoid,
        body: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 20),
              const Text('STEP 2 (new)', style: TextStyle(color: Colors.white)),
              buildHelpDialog(
                'Manual setup',
                "find ~/Documents/Git -maxdepth 3 -name '*.git' -type d",
                [
                  '1. Auto setup: type any path here (e.g. ~/Documents/Git/localsync.git) - created automatically the first time you pair',
                  '2. Manual setup (auto failed, or reusing an existing folder): run this command on the desktop terminal',
                  '3. Lists every desktop sync folder on the desktop',
                  '4. More than one listed? The one you set up first is usually right',
                ],
              ),
              const SizedBox(height: 40),
              const Text('STEP 3 (existing, reference style)', style: TextStyle(color: Colors.white)),
              buildHelpDialog(
                'Manual setup',
                'ip -4 addr show',
                [
                  '1. Run this command on the desktop terminal',
                  '2. Find your interface in the result, looking like:\n"n: eth1: inet 172.20.10.11/28" or\n"n: usb0: inet 172.20.10.11/28"',
                  '3. Type just the 4 numbers into the IP address field above (e.g. 172.20.10.11) - no /28 suffix',
                  '4. Changed from USB cable to Wi-Fi Hotspot, or reconnecting later? Re-run this command - the address can change',
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/manual_setup_dialogs_preview.png'),
    );
  });
}
