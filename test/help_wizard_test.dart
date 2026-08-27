// Verifies the branching help wizard's actual logic (help_wizard.dart).
// Flow A (Home) is a 3-button picker leading to a read-only workflow
// summary - no per-step buttons, since PUSH/PULL are a swipe on the
// real Home screen, not something this dialog performs. Flow B
// (Conflicts) stays a tap-through, one-question-per-card wizard.
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
    expect(find.descendant(
        of: find.byKey(const ValueKey('choices')),
        matching: find.byType(Expanded)), findsNWidgets(3));

    expect(find.text('BOTH\nEDITED'), findsOneWidget);
    expect(find.text('DESKTOP\nEDITED'), findsOneWidget);
    expect(find.text('PHONE\nEDITED'), findsOneWidget);
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
        find.text('Your OTHER device must receive the data - not this '
            'LocalSync app.'),
        findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
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
        find.text('Your OTHER device must send its data - phone LocalSync '
            'app is next.'),
        findsOneWidget);
    expect(find.text('Phone PULL'), findsOneWidget);
    expect(find.text('Phone PUSH'), findsNothing);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets(
      'Flow A: BOTH EDITED -> Phone PUSH, Desktop PUSH, Phone PULL, Done + Flow B footnote',
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
    expect(
        find.text('If conflicts show after pulling, resolve them first - '
            'see Flow B.'),
        findsOneWidget);
  });

  testWidgets('Flow A: back link returns to the picker', (tester) async {
    await tester.pumpWidget(_harness('A'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('BOTH\nEDITED'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.text('WORKFLOW'), findsOneWidget);

    await tester.tap(find.text('< back'));
    await tester.pumpAndSettle();

    expect(find.text('BOTH\nEDITED'), findsOneWidget);
    expect(find.text('WORKFLOW'), findsNothing);
  });

  testWidgets('Flow A: close button dismisses from the picker', (tester) async {
    await tester.pumpWidget(_harness('A'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('BOTH\nEDITED'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
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
        find.text('Not picked ≠ deleted - saved under Conflict Backups.'),
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

  testWidgets('Flow B: close button dismisses the dialog', (tester) async {
    await tester.pumpWidget(_harness('B'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Any conflicts?'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('Any conflicts?'), findsNothing);
  });
}
