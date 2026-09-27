// Local visual verification only - the "Desktop found" progress panel in
// the yellow box after a complete QR scan (settings_screen.dart). Run with:
//   flutter test test/scan_continue_panel_preview_test.dart --update-goldens
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/screens/settings_screen.dart';

void main() {
  testWidgets('Desktop found panel in the yellow box, bar half full',
      (tester) async {
    tester.view.physicalSize = const Size(1170, 1200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: const Color(0xFFFFC107),
                borderRadius: BorderRadius.circular(12)),
            child: ScanContinuePanel(
              user: 'rapi5',
              ip: '172.20.10.2',
              syncFolder:
                  '/home/rapi5/Documents/Git/pi5-obsidian/Git_bare_repo/Md_files_bare.git',
              vaultPath: '/home/rapi5/Documents/Obsidian_vault',
              progress: const AlwaysStoppedAnimation(0.3),
              onBanner: true,
              onCancel: () {},
              onContinue: () {},
            ),
          ),
        ),
      ),
    ));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/scan_continue_panel.png'));
  });
}
