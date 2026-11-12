// widgets/password_mismatch_marks.dart
//
// 2026-11-12 owner: "use the kworld email match wrong character helper" for the confirm password. Dart port of the
// website's src/lib/email_mismatch.ts. The password fields hide their text, so the marks are the marks are drawn by
// ShreddingPasswordField over its own dots; this file holds the detection only.

enum MismatchKind { sub, extra, missing }

class Mismatch {
  final MismatchKind kind;
  final int idx;
  const Mismatch(this.kind, this.idx);
}

/// Only reports once the typing looks finished (within one character of the full length), so it never fights a
/// half-typed password.
Mismatch? textMismatch(String typed, String want) {
  if (typed.isEmpty || want.isEmpty || typed == want || typed.length < want.length - 1) return null;
  var p = 0;
  while (p < typed.length && p < want.length && typed[p] == want[p]) {
    p++;
  }
  if (p == typed.length) {
    return typed.length == want.length - 1 ? Mismatch(MismatchKind.missing, p) : null;
  }
  if (typed.length > want.length) {
    return typed.substring(0, p) + typed.substring(p + 1) == want
        ? Mismatch(MismatchKind.extra, p)
        : Mismatch(MismatchKind.sub, p);
  }
  if (typed.length < want.length) {
    return typed.substring(0, p) + want[p] + typed.substring(p) == want
        ? Mismatch(MismatchKind.missing, p)
        : Mismatch(MismatchKind.sub, p);
  }
  return Mismatch(MismatchKind.sub, p);
}
