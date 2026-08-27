// Verifies the branching help wizard's actual logic (help_wizard.dart).
// Flow A (Home) is a 3-button picker leading to a read-only workflow
// summary - no per-step buttons, since PUSH/PULL are a swipe on the
// real Home screen, not something this dialog performs, and no close/
// back controls either - showDialog is barrier-dismissible by default,
// so tapping outside already works and duplicate controls were dropped.
// Flow B (Conflicts) stays a tap-through, one-question-per-card wizard.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/widgets/help_wizard.dart';

Widget _harness(String flow) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showHelpWizard(context, flow),
          child: const Text('open'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('Flow A: opens on the 3-button picker, alphabetical order',
      (tester) async {
    await tester.pumpWidget(_harness('A'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Horizontal row of 3 buttons, not a vertical stack.
    expect(find.byKey(const ValueKey('choices')), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('choices')),
            matching: find.byType(Expanded)),
        findsNWidgets(3));

    expect(find.text('BOTH\nEDITED'), findsOneWidget);
    expect(find.text('DESKTOP\nEDITED'), findsOneWidget);
    expect(find.text('PHONE\nEDITED'), findsOneWidget);
    // No X, no separate dismiss control - barrier tap handles it.
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('Flow A: PHONE EDITED -> Phone PUSH, Desktop PULL (with note), Done',
      (tester) async {
    await tester.pumpWidget(_harness('A'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('PHONE\nEDITED'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    expect(find.text('WORKFLOW'), findsOneWidget);
    expect(find.text('Phone PUSH'), findsOneWidget);
    expect(find.text('Desktop PULL'), findsOneWidget);
    expect(
        find.text('Your OTHER device (computer/desktop/laptop) must '
            'receive the data - not this LocalSync app.'),
        findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    // No back link any more.
    expect(find.text('< back'), findsNothing);
    // PHONE never runs Phone PULL, so it can't actually produce a
    // conflict - no hint pointing at Conflicts here.
    expect(find.textContaining('Conflicts'), findsNothing);
  });

  testWidgets(
      'Flow A: DESKTOP EDITED -> Desktop PUSH (with note), Phone PULL, Done - no push needed',
      (tester) async {
    await tester.pumpWidget(_harness('A'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('DESKTOP\nEDITED'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    expect(find.text('Desktop PUSH'), findsOneWidget);
    expect(
        find.text('Your OTHER device (computer/desktop/laptop) must send '
            'its data first - phone LocalSync app is after this step.'),
        findsOneWidget);
    expect(find.text('Phone PULL'), findsOneWidget);
    expect(find.text('Phone PUSH'), findsNothing);
    expect(find.text('Done'), findsOneWidget);
    // Runs Phone PULL, so a real conflict is possible here.
    expect(find.text('If conflicts show: tap ⋮ then Conflicts.'),
        findsOneWidget);
  });

  testWidgets(
      'Flow A: BOTH EDITED -> Phone PUSH, Desktop PUSH, Phone PULL, Done - no "Flow B" footnote',
      (tester) async {
    await tester.pumpWidget(_harness('A'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('BOTH\nEDITED'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    expect(find.text('Phone PUSH'), findsOneWidget);
    expect(find.text('Desktop PUSH'), findsOneWidget);
    expect(find.text('Phone PULL'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    // "Flow B" is internal design-doc shorthand, never a name a real
    // user has seen in this app - the footnote naming it was dropped.
    expect(find.textContaining('Flow B'), findsNothing);
    // Runs Phone PULL, so a real conflict is possible here too.
    expect(find.text('If conflicts show: tap ⋮ then Conflicts.'),
        findsOneWidget);
  });

  testWidgets('Flow A: tapping outside the dialog dismisses it (barrier default)',
      (tester) async {
    await tester.pumpWidget(_harness('A'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('BOTH\nEDITED'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5)); // outside the dialog card
    await tester.pumpAndSettle();

    expect(find.text('BOTH\nEDITED'), findsNothing);
  });

  testWidgets(
      'Flow B: pick version shows the not-deleted reassurance, loop repeats, then Done',
      (tester) async {
    await tester.pumpWidget(_harness('B'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Any conflicts?'), findsOneWidget);
    await tester.tap(find.text('YES'));
    await tester.pumpAndSettle();

    expect(find.text('Pick version'), findsOneWidget);
    expect(
        find.text("Not picked doesn't delete text, rather data is saved in "
            'Obsidian vault/LocalSync/Conflict Backups/note.'),
        findsOneWidget);
    await tester.tap(find.text('CONTINUE'));
    await tester.pumpAndSettle();

    expect(find.text('More conflicts?'), findsOneWidget);
    // Loop back for a second conflict.
    await tester.tap(find.text('YES'));
    await tester.pumpAndSettle();
    expect(find.text('Pick version'), findsOneWidget);
    await tester.tap(find.text('CONTINUE'));
    await tester.pumpAndSettle();

    // No more conflicts this time.
    await tester.tap(find.text('NO'));
    await tester.pumpAndSettle();

    expect(find.text('PUSH'), findsOneWidget);
    await tester.tap(find.text('CONTINUE'));
    await tester.pumpAndSettle();

    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('Flow B: no conflicts -> Nothing to do', (tester) async {
    await tester.pumpWidget(_harness('B'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('NO'));
    await tester.pumpAndSettle();

    expect(find.text('Nothing to do'), findsOneWidget);
  });

  testWidgets('Flow B: no close icon - tapping outside dismisses it',
      (tester) async {
    await tester.pumpWidget(_harness('B'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Any conflicts?'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.text('Any conflicts?'), findsNothing);
  });
}
