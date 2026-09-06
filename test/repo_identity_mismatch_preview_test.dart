// Local visual check for the repoIdentityMismatch error screen -
// real feedback, live: "show me a preview so errors can be easily
// seen and fixed by users." Renders the exact same DiagCard stack
// linking_screen.dart's failure view uses, with the real diagnosis/
// resolution text from linking_state.dart and a real example
// debugDetail (both raw paths + the human name, per the same-day fix
// that made this always populate instead of only when a name file
// happened to be reachable).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/theme.dart';
import 'package:localsync/widgets/diag_card.dart';

void main() {
  testWidgets('repoIdentityMismatch - WHAT HAPPENED + HOW TO FIX IT + RAW ERROR',
      (tester) async {
    tester.view.physicalSize = const Size(1170, 2500);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: kVoid,
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Something stopped',
                  style: TextStyle(
                      color: kStar,
                      fontSize: 24,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 20),
              DiagCard(
                label: 'WHAT HAPPENED',
                text: 'This vault folder is already linked to a different '
                    'bare repo than the one in Settings.',
                accent: Colors.redAccent,
              ),
              const SizedBox(height: 12),
              DiagCard(
                label: 'HOW TO FIX IT',
                text: 'If you meant to switch repos, that\'s fine - but '
                    'check Settings\' Git bare repo path is really what '
                    'you want first.\n'
                    'If you didn\'t mean to change it, fix the path in '
                    'Settings back to what this folder was already '
                    'using, then try again.',
                accent: kGreen,
                icon: Icons.lightbulb_outline,
                bulleted: true,
              ),
              const SizedBox(height: 12),
              DiagCard(
                label: 'RAW ERROR (TEMPORARY DIAGNOSTIC)',
                text: 'Currently connected to: "Md Files Bare"\n'
                    'This folder\'s repo: /home/rapi5/Documents/Git/'
                    'pi5-obsidian/Git_bare_repo/Md_files_bare.git\n'
                    'Settings\' repo: /home/rapi5/Documents/Git/'
                    'localsync.git',
                accent: kTextMid,
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
      matchesGoldenFile('goldens/repo_identity_mismatch.png'),
    );
  });
}
