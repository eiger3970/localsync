import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/services/word_diff.dart';

String marked(List<DiffToken> ts) =>
    ts.map((t) => t.op == DiffOp.equal ? t.text : '[${t.text}]').join();

void main() {
  test('stray shared small words in unrelated text count as different', () {
    const a = 'Only room for dessert, a cup of orange.';
    const b = 'Seat filling agencies for the mortgage.';
    final ours = wordDiffOurs(a, b);
    expect(ours.where((t) => t.op == DiffOp.equal && t.text == 'for'),
        isEmpty);
    // text on each side is unchanged, only its marking
    expect(ours.map((t) => t.text).join(), a);
    expect(wordDiffTheirs(a, b).map((t) => t.text).join(), b);
  });

  test('a real shared sentence stays unhighlighted', () {
    const a = 'Hello there. Invite the testers today. Bye';
    const b = 'Hi. Invite the testers today. See you';
    final m = marked(wordDiffOurs(a, b));
    expect(m, contains('Invite the testers today.'));
    expect(m, isNot(contains('[Invite]')));
  });
}
