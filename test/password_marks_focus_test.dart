import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/widgets/shredding_password_field.dart';

void main() {
  keepsFocus();
  noEarlyOverwrite();
  testWidgets('focus selects the first wrong character; typing over it moves on', (t) async {
    final c = TextEditingController(text: 'tord');
    final f = FocusNode();
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ShreddingPasswordField(controller: c, focusNode: f, markAgainst: 'word', showOwnBorder: false),
      ),
    ));
    await t.pump(const Duration(milliseconds: 400)); // settle
    f.requestFocus();
    await t.pump(const Duration(milliseconds: 200));
    expect(c.selection.baseOffset, 0);
    expect(c.selection.extentOffset, 1);
    // type the right letter over the highlighted one: now equal, no marks
    await t.enterText(find.byType(TextField), 'word');
    await t.pump(const Duration(milliseconds: 400));
    expect(c.text, 'word');
  });
}

void keepsFocus() {
  testWidgets('keyboard focus survives marks appearing and disappearing, and field 1 highlights too', (t) async {
    final c1 = TextEditingController(text: 'tord');
    final c2 = TextEditingController(text: 'word');
    final f1 = FocusNode(), f2 = FocusNode();
    late StateSetter set;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (_, s) {
          set = s;
          return Column(children: [
            ShreddingPasswordField(controller: c1, focusNode: f1, markAgainst: c2.text, markIsFirst: true, showOwnBorder: false),
            ShreddingPasswordField(controller: c2, focusNode: f2, markAgainst: c1.text, showOwnBorder: false),
          ]);
        }),
      ),
    ));
    await t.pump(const Duration(milliseconds: 400));
    f1.requestFocus();
    await t.pump(const Duration(milliseconds: 200));
    expect(c1.selection.baseOffset, 0);
    expect(c1.selection.extentOffset, 1);
    // fix field 1 while it has focus: marks vanish, focus must stay
    c1.text = 'word';
    set(() {});
    await t.pump(const Duration(milliseconds: 500));
    expect(f1.hasFocus, isTrue);
    // break it again: marks reappear, focus must still stay
    c1.text = 'wprd';
    set(() {});
    await t.pump(const Duration(milliseconds: 500));
    expect(f1.hasFocus, isTrue);
  });
}

void noEarlyOverwrite() {
  testWidgets('a pause while still typing never selects a character; a real pause does', (t) async {
    final c1 = TextEditingController(text: 'test@rest.com');
    final c2 = TextEditingController();
    final f2 = FocusNode();
    late StateSetter set;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (_, s) {
          set = s;
          return ShreddingPasswordField(controller: c2, focusNode: f2, markAgainst: c1.text, showOwnBorder: false);
        }),
      ),
    ));
    f2.requestFocus();
    await t.pump();
    await t.enterText(find.byType(TextField), 'test@test.co'); // one short: user still typing
    await t.pump(const Duration(milliseconds: 1700));
    expect(c2.selection.isCollapsed, isTrue, reason: 'no highlight while one character short');
    await t.enterText(find.byType(TextField), 'test@test.com');
    await t.pump(const Duration(milliseconds: 600)); // short pause
    expect(c2.selection.isCollapsed, isTrue, reason: 'no highlight after a short pause');
    await t.pump(const Duration(milliseconds: 1500)); // real pause
    expect(c2.selection.baseOffset, 5);
    expect(c2.selection.extentOffset, 6);
  });
}
