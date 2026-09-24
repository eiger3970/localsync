// Local visual verification only - setup checklists with the per-step
// app badges (widgets/app_badge.dart). Run with:
//   flutter test test/setup_checklist_preview_test.dart --update-goldens
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/features/linking/linking_controller.dart';
import 'package:localsync/screens/linking_screen.dart';
import 'package:localsync/theme.dart';

void main() {
  testWidgets('create vault + pick vault checklists', (tester) async {
    tester.view.physicalSize = const Size(390, 1250);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final ctrl = LinkingController(
        desktopUser: 'u', desktopIp: '1.2.3.4', bareRepoPath: '');
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        backgroundColor: kVoid,
        body: ListView(padding: const EdgeInsets.all(12), children: [
          StepChecklist(groupNumber: 1, steps: ctrl.vaultCreationSteps),
          const SizedBox(height: 12),
          StepChecklist(groupNumber: 2, steps: ctrl.vaultFolderSteps),
        ]),
      ),
    ));
    await tester.pump();
    // The checklist's CheckboxListTiles sit in a coloured box - a
    // long-standing debug-only ink-splash warning, not from this change.
    while (tester.takeException() != null) {}
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/setup_checklists.png'));
  });
}
