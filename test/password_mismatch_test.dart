import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/widgets/password_mismatch_marks.dart';

void main() {
  test('substitution, missing, extra, silent when half-typed or equal', () {
    expect(textMismatch('abcxef', 'abcdef')!.kind, MismatchKind.sub);
    expect(textMismatch('abcxef', 'abcdef')!.idx, 3);
    expect(textMismatch('abdef', 'abcdef')!.kind, MismatchKind.missing);
    expect(textMismatch('abcdeff', 'abcdef')!.kind, MismatchKind.extra);
    expect(textMismatch('abc', 'abcdef'), isNull);
    expect(textMismatch('abcdef', 'abcdef'), isNull);
  });

  test('2026-11-13: a typed start matches the FIRST equal letters (no marks on correct characters)', () {
    List<String> ops(String a, String b) => [for (final o in diffOps(a, b)) '${o.kind.name}${o.i}'];
    expect(ops('t', 'test@rest.cno').where((o) => !o.endsWith('1')), isEmpty);
    expect(ops('te', 'test@rest.cno').where((o) => !o.endsWith('2')), isEmpty);
    expect(ops('test@test.come', 'test@test.com'), ['extra13']);
    expect(ops('test@test.com', 'test@test.come'), ['missing13']);
    expect(ops('test@rest.cno', 'test@test.cno'), ['sub5']);
  });
}
