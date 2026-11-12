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

/// 2026-11-12 owner: align the two texts (Levenshtein) so extra and missing characters are found as well as wrong ones.
/// Same algorithm as the website's diffOps (MatchEasy).
class MmOp {
  final MismatchKind kind;
  final int i;
  const MmOp(this.kind, this.i);
}

List<MmOp> diffOps(String typed, String want) {
  final n = typed.length, m = want.length;
  if (typed == want) return const [];
  if (n > 400 || m > 400) {
    return [
      for (var i = 0; i < n && i < m; i++)
        if (typed[i] != want[i]) MmOp(MismatchKind.sub, i),
      for (var i = m; i < n; i++) MmOp(MismatchKind.extra, i),
      if (m > n) MmOp(MismatchKind.missing, n),
    ];
  }
  final d = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = 0; i <= n; i++) {
    d[i][0] = i;
  }
  for (var j = 0; j <= m; j++) {
    d[0][j] = j;
  }
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      final a = d[i - 1][j - 1] + (typed[i - 1] == want[j - 1] ? 0 : 1);
      final b = d[i - 1][j] + 1, c = d[i][j - 1] + 1;
      d[i][j] = a < b ? (a < c ? a : c) : (b < c ? b : c);
    }
  }
  final ops = <MmOp>[];
  var i = n, j = m;
  while (i > 0 || j > 0) {
    if (i > 0 && j > 0 && typed[i - 1] == want[j - 1] && d[i][j] == d[i - 1][j - 1]) {
      i--;
      j--;
    } else if (i > 0 && j > 0 && d[i][j] == d[i - 1][j - 1] + 1) {
      ops.add(MmOp(MismatchKind.sub, i - 1));
      i--;
      j--;
    } else if (i > 0 && d[i][j] == d[i - 1][j] + 1) {
      ops.add(MmOp(MismatchKind.extra, i - 1));
      i--;
    } else {
      ops.add(MmOp(MismatchKind.missing, i));
      j--;
    }
  }
  return ops.reversed.toList();
}

/// Did the edit prev -> next fix exactly the first op? Then the highlight carries on with no delay.
bool fixedFirst(String prev, String next, MmOp? op) {
  if (op == null) return false;
  final i = op.i;
  switch (op.kind) {
    case MismatchKind.sub:
      return next.length == prev.length &&
          i < next.length &&
          next[i] != prev[i] &&
          next.substring(0, i) == prev.substring(0, i) &&
          next.substring(i + 1) == prev.substring(i + 1);
    case MismatchKind.extra:
      return next == prev.substring(0, i) + prev.substring(i + 1);
    case MismatchKind.missing:
      return next.length == prev.length + 1 &&
          next.substring(0, i) == prev.substring(0, i) &&
          next.substring(i + 1) == prev.substring(i);
  }
}
