// services/word_diff.dart
//
// 2026-08-18: "vimdiff instant visuals... rather than concentrated heavy
// reading" - word-level diff so a conflict picker can highlight exactly
// what differs instead of making the user read two full blocks side by
// side. Plain LCS, not a new pub dependency - this app otherwise has
// zero general-utility packages (every dependency is load-bearing:
// git2dart, ssh, crypto), and a word-diff over a few lines of conflict
// text is a small, well-understood algorithm, not worth a new package
// for.

enum DiffOp { equal, deleteOnly, insertOnly }

class DiffToken {
  final DiffOp op;
  final String text;
  const DiffToken(this.op, this.text);
}

final _tokenPattern = RegExp(r'\S+|\s+');

List<String> _tokenize(String s) =>
    _tokenPattern.allMatches(s).map((m) => m[0]!).toList();

/// Longest-common-subsequence word diff between [a] (e.g. "yours") and
/// [b] (e.g. "theirs"). [equal] tokens appear in both outputs unchanged;
/// [deleteOnly] only makes sense rendered against [a], [insertOnly] only
/// against [b] - see wordDiffForSide below, which is what callers
/// actually want.
///
/// O(n*m) - fine for a few lines of conflict text, not meant for whole
/// documents. [maxTokens] caps input size; callers should fall back to
/// plain (unhighlighted) text if either side exceeds it.
const maxDiffTokens = 400;

List<DiffToken> _diff(String a, String b) {
  final ta = _tokenize(a), tb = _tokenize(b);
  final n = ta.length, m = tb.length;
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      dp[i][j] = ta[i] == tb[j]
          ? dp[i + 1][j + 1] + 1
          : (dp[i + 1][j] > dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
    }
  }
  final result = <DiffToken>[];
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (ta[i] == tb[j]) {
      result.add(DiffToken(DiffOp.equal, ta[i]));
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      result.add(DiffToken(DiffOp.deleteOnly, ta[i]));
      i++;
    } else {
      result.add(DiffToken(DiffOp.insertOnly, tb[j]));
      j++;
    }
  }
  while (i < n) {
    result.add(DiffToken(DiffOp.deleteOnly, ta[i]));
    i++;
  }
  while (j < m) {
    result.add(DiffToken(DiffOp.insertOnly, tb[j]));
    j++;
  }
  return _dropStrayMatches(result);
}

/// 2026-09-27: user - "a few words aren't highlighted green, like to and
/// for, what's the reason and meaning?" Two unrelated texts still share
/// small words ("to", "for", "a") in the same order, and plain LCS
/// counted each one as shared text - islands of "same" inside text that
/// is entirely different. A shared run shorter than [minRun] words, with
/// differences on both sides of it, is now shown as different on both
/// sides. Real shared sentences (3+ words in a row) stay unhighlighted.
List<DiffToken> _dropStrayMatches(List<DiffToken> tokens, {int minRun = 3}) {
  final out = <DiffToken>[];
  var k = 0;
  while (k < tokens.length) {
    if (tokens[k].op != DiffOp.equal) {
      out.add(tokens[k]);
      k++;
      continue;
    }
    final start = k;
    while (k < tokens.length && tokens[k].op == DiffOp.equal) {
      k++;
    }
    final run = tokens.sublist(start, k);
    final words = run.where((t) => t.text.trim().isNotEmpty).length;
    final between = start > 0 && k < tokens.length;
    if (words > 0 && words < minRun && between) {
      for (final t in run) {
        out.add(DiffToken(DiffOp.deleteOnly, t.text));
      }
      for (final t in run) {
        out.add(DiffToken(DiffOp.insertOnly, t.text));
      }
    } else {
      out.addAll(run);
    }
  }
  return out;
}

/// Tokens to render for the "ours" side: equal text plain, deleteOnly
/// text marked as "differs here" (nothing rendered for insertOnly -
/// that text simply isn't on this side).
List<DiffToken> wordDiffOurs(String ours, String theirs) => _diff(ours, theirs)
    .where((t) => t.op != DiffOp.insertOnly)
    .toList();

/// Tokens to render for the "theirs" side - mirror of wordDiffOurs.
List<DiffToken> wordDiffTheirs(String ours, String theirs) =>
    _diff(ours, theirs).where((t) => t.op != DiffOp.deleteOnly).toList();
