import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/widgets/shredding_password_field.dart';

void main() {
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
