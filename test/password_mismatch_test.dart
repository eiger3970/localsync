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
}
