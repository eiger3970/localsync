// services/line_diff.dart
//
// 2026-08-26: "automatic put/yank individual pieces from each side" -
// the premium merge tier from docs/pricing-tiers.md. word_diff.dart
// diffs at word granularity for inline highlighting inside a single
// paragraph (conflict_picker_screen.dart's vimdiff view) - too fine a
// grain to pick from, toggling individual words rarely produces
// coherent prose. Real vimdiff's own dp/do commands operate on raw
// file lines - but this app's notes are prose, usually one long line
// per paragraph (no manual hard-wraps), so a pure line-unit diff would
// rarely split a paragraph at all. Sentence is the unit that actually
// produces multiple pickable pieces within one differing paragraph -
// "let every sentence be merged and in the right place" - while
// paragraph breaks are still respected as hard boundaries (sentence
// diffing only refines within a single ours-paragraph vs
// single-theirs-paragraph pairing; a paragraph inserted or removed
// wholesale stays a whole-paragraph hunk - diffing sentences across
// multiple concatenated paragraphs isn't a meaningful comparison).

enum HunkOp { same, conflict }

/// One unit of the merge. [same] hunks aren't a choice - identical text
/// on both sides, always included. [conflict] hunks are where the two
/// sides actually differ - [ours] and [theirs] hold that hunk's text on
/// each side, for the caller to pick between.
class MergeHunk {
  final HunkOp op;
  final String ours;
  final String theirs;
  // 2026-08-26: which original paragraph this hunk came from - several
  // consecutive sentence hunks share one paragraphGroup (that paragraph
  // was refined into sentences), a same/multi-paragraph hunk is its own
  // group. composeMerge uses this to know where a real paragraph break
  // belongs versus where sentence hunks should just butt up against
  // each other with no separator - simpler and more robust than
  // inferring it from whitespace after the fact.
  final int paragraphGroup;
  const MergeHunk({
    required this.op,
    required this.ours,
    this.theirs = '',
    required this.paragraphGroup,
  });
}

/// Caps input size the same way word_diff.dart's maxDiffTokens does -
/// O(n*m) LCS, fine for a note's worth of paragraphs/sentences, not
/// meant for arbitrarily large documents. Callers should fall back to
/// the existing whole-side picker above this for anything larger.
const maxMergeUnits = 400;

enum _Op { equal, oursOnly, theirsOnly }

/// Generic paragraph-or-sentence-level LCS, structurally identical to
/// word_diff.dart's _diff - see that file's comment for why LCS
/// specifically (simple, well-understood, no new dependency).
List<(_Op, String)> _diffUnits(List<String> a, List<String> b) {
  final n = a.length, m = b.length;
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      dp[i][j] = a[i] == b[j]
          ? dp[i + 1][j + 1] + 1
          : (dp[i + 1][j] > dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
    }
  }
  final result = <(_Op, String)>[];
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      result.add((_Op.equal, a[i]));
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      result.add((_Op.oursOnly, a[i]));
      i++;
    } else {
      result.add((_Op.theirsOnly, b[j]));
      j++;
    }
  }
  while (i < n) {
    result.add((_Op.oursOnly, a[i]));
    i++;
  }
  while (j < m) {
    result.add((_Op.theirsOnly, b[j]));
    j++;
  }
  return result;
}

class _RawHunk {
  final HunkOp op;
  final List<String> ours;
  final List<String> theirs;
  const _RawHunk(this.op, this.ours, this.theirs);
}

/// Groups raw per-unit diff ops into hunks: a maximal run of
/// oursOnly/theirsOnly units becomes one conflict hunk, so a passage
/// that shifted position on one side still reads as one choice, not
/// several fragmentary ones. Keeps the individual unit lists (not yet
/// joined into one string) so the caller can tell how many units
/// contributed - see mergeHunks' sentence-refinement decision below.
List<_RawHunk> _groupHunks(List<(_Op, String)> diffed) {
  final hunks = <_RawHunk>[];
  final oursGroup = <String>[];
  final theirsGroup = <String>[];

  void flushConflict() {
    if (oursGroup.isEmpty && theirsGroup.isEmpty) return;
    hunks.add(_RawHunk(HunkOp.conflict, [...oursGroup], [...theirsGroup]));
    oursGroup.clear();
    theirsGroup.clear();
  }

  for (final (op, text) in diffed) {
    switch (op) {
      case _Op.equal:
        flushConflict();
        hunks.add(_RawHunk(HunkOp.same, [text], [text]));
      case _Op.oursOnly:
        oursGroup.add(text);
      case _Op.theirsOnly:
        theirsGroup.add(text);
    }
  }
  flushConflict();
  return hunks;
}

List<String> _paragraphs(String s) => s.split('\n\n');

/// Sentence split that preserves exact text on concatenation - each
/// match includes its own trailing punctuation and whitespace, so
/// joining a side's sentence chunks back together with '' reproduces
/// that side's original paragraph exactly. Deliberately simple (splits
/// on ./!/? regardless of abbreviations like "e.g." or "Mr.") - same
/// pragmatic-over-perfect bias as word_diff.dart's own plain-LCS choice,
/// a wrong split just means one hunk is a little larger than ideal, not
/// a real bug.
final _sentencePattern = RegExp(r'[^.!?]*[.!?]+\s*|[^.!?]+$', dotAll: true);

List<String> _sentences(String paragraph) {
  final matches = _sentencePattern
      .allMatches(paragraph)
      .map((m) => m[0]!)
      .where((s) => s.isNotEmpty)
      .toList();
  return matches.isEmpty ? [paragraph] : matches;
}

/// Paragraph-level hunks first (so paragraph breaks are never crossed or
/// reordered), then for any conflict hunk that's cleanly one
/// ours-paragraph against one theirs-paragraph, refined further into
/// sentence-level hunks - that's the case an edit to a couple of
/// sentences inside an otherwise-unchanged paragraph produces, and the
/// one sentence-diffing actually makes sense for. A hunk spanning
/// multiple paragraphs on either side (a whole paragraph added or
/// removed) stays a single whole-paragraph hunk instead - diffing
/// sentences across concatenated paragraphs isn't a meaningful
/// comparison.
List<MergeHunk> mergeHunks(String ours, String theirs) {
  final paragraphHunks =
      _groupHunks(_diffUnits(_paragraphs(ours), _paragraphs(theirs)));
  final result = <MergeHunk>[];
  var group = 0;

  for (final h in paragraphHunks) {
    if (h.op == HunkOp.same) {
      result.add(
          MergeHunk(op: HunkOp.same, ours: h.ours.single, paragraphGroup: group));
      group++;
      continue;
    }
    if (h.ours.length == 1 && h.theirs.length == 1) {
      final sentenceHunks = _groupHunks(
          _diffUnits(_sentences(h.ours.single), _sentences(h.theirs.single)));
      for (final sh in sentenceHunks) {
        result.add(MergeHunk(
          op: sh.op,
          ours: sh.ours.join(),
          theirs: sh.op == HunkOp.same ? sh.ours.join() : sh.theirs.join(),
          paragraphGroup: group,
        ));
      }
      group++;
      continue;
    }
    result.add(MergeHunk(
      op: HunkOp.conflict,
      ours: h.ours.join('\n\n'),
      theirs: h.theirs.join('\n\n'),
      paragraphGroup: group,
    ));
    group++;
  }
  return result;
}

/// Composes the final merged text from [hunks] given which conflict
/// hunks (by index into [hunks]) should take theirs instead of the
/// default ours. A hunk with neither side "chosen" still needs a
/// value to compose with - defaulting to ours (never blank) means an
/// unreviewed hunk fails safe to "nothing changes here" rather than
/// silently dropping content, same safety bias as every other merge
/// path in this app.
///
/// Hunks sharing a paragraphGroup (sentence hunks refined from one
/// paragraph) join with no separator - each sentence already carries
/// its own trailing whitespace (see _sentences). A new paragraphGroup
/// starts a real paragraph break.
String composeMerge(List<MergeHunk> hunks, Set<int> theirsChosen) {
  final buffer = StringBuffer();
  int? lastGroup;
  for (var i = 0; i < hunks.length; i++) {
    final h = hunks[i];
    final text = h.op == HunkOp.same
        ? h.ours
        : (theirsChosen.contains(i) ? h.theirs : h.ours);
    if (text.isEmpty) continue;
    if (buffer.isNotEmpty && lastGroup != h.paragraphGroup) buffer.write('\n\n');
    buffer.write(text);
    lastGroup = h.paragraphGroup;
  }
  return buffer.toString();
}
