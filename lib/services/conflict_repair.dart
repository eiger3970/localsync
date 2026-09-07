// services/conflict_repair.dart
//
// 2026-08-19: pulled out of sync_service.dart's private conflict-repair
// section so this logic - pure string transforms, no dart:io, no
// git2dart, no Flutter - can be unit-tested directly. Everything below
// was previously underscore-private inside sync_service.dart, which
// meant it could only ever be exercised through a full pull()/push()
// round trip against a real bare repo - never actually run in a test,
// only ever verified by real device sideloads. See test/
// conflict_repair_test.dart, added the same day as this file, which
// specifically exercises the nested/compounding-conflict-marker bug
// this same session fixed.
//
// Ports /home/rapi5/Documents/Scripts/repair_conflicts.py's real
// strategy (not an earlier trimmed-down version this file used to
// have) - triggered after git2dart's Merge.commit instead of `git
// merge`. Operates on working-directory files as plain text, not
// git's index/tree objects.

final fullConflictPattern = RegExp(
  r'^<<<<<<< [^\n]*\n(.*?)\n=======\n(.*?)\n>>>>>>> [^\n]*\n?',
  multiLine: true,
  dotAll: true,
);
final partialConflictPattern = RegExp(r'^<<<<<<< [^\n]*\n', multiLine: true);
final kanbanFrontmatterPattern = RegExp(r'^kanban-plugin:', multiLine: true);

String normalizeWhitespace(String text) =>
    text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Mirrors repair_conflicts.py's dedupe_and_check_append(): if theirs'
/// lines, once the overlap with the end of ours is removed, don't
/// duplicate anything already in ours, they're a clean additive change
/// (both devices appended different new lines) - append with no
/// conflict callout. Returns null if this auto-merge doesn't apply and
/// the real conflict-callout fallback is needed.
String? dedupeAndCheckAppend(String ours, String theirs) {
  final oursLines = ours.split('\n');
  final theirsLines = theirs.split('\n');
  var overlap = 0;
  final maxCheck = oursLines.length < theirsLines.length
      ? oursLines.length
      : theirsLines.length;
  for (var i = 1; i <= maxCheck; i++) {
    final oursTail = oursLines.sublist(oursLines.length - i);
    final theirsHead = theirsLines.sublist(0, i);
    var equal = true;
    for (var j = 0; j < i; j++) {
      if (oursTail[j] != theirsHead[j]) {
        equal = false;
        break;
      }
    }
    if (equal) overlap = i;
  }
  final remaining = theirsLines.sublist(overlap);
  if (remaining.every((l) => l.trim().isEmpty)) return ours;

  // 2026-08-17: real device bug - two sibling edits to the same line (e.g.
  // both sides rewrote line 1 to different text) have overlap == 0 (no
  // shared prefix at all between ours/theirs), yet "theirs isn't a
  // duplicate substring of ours" trivially passes for any two different
  // strings - meaning every genuine same-line conflict silently fell
  // through to a plain append with no warning callout, instead of ever
  // reaching the real conflict UI below. Requiring overlap > 0 means
  // theirs must genuinely be "ours plus more" (one side's edit is a
  // continuation/superset of the other's) - the actual case this was
  // meant for - not just "text that happens to differ".
  if (overlap == 0) return null;

  final oursSet =
      oursLines.map((l) => l.trim()).where((l) => l.isNotEmpty).toSet();
  final remainingNonBlank = remaining.where((l) => l.trim().isNotEmpty).toList();
  if (remainingNonBlank.isNotEmpty &&
      remainingNonBlank.every((l) => !oursSet.contains(l.trim()))) {
    final theirsRemaining = remaining.join('\n').trim();
    return chronologicallyOrderedIfJournal(ours, theirsRemaining) ??
        '$ours\n\n$theirsRemaining';
  }
  return null;
}

final _journalTimePattern = RegExp(r'^(\d{4})\b');

List<String> _splitParagraphs(String text) => text
    .split(RegExp(r'\n\s*\n'))
    .map((p) => p.trim())
    .where((p) => p.isNotEmpty)
    .toList();

/// 2026-09-07: real feedback, live - two unrelated journal entries
/// (each a paragraph starting with a bare HHMM time, this user's real
/// journal convention - "2105 salad...", "0715 I left...") landing on
/// opposite sides of an auto-merge used to just concatenate ours-then-
/// theirs regardless of what time of day either actually happened,
/// so an earlier entry could land stacked below a later one. When
/// every paragraph on both sides matches that exact HHMM shape, this
/// re-sorts the combined paragraphs chronologically instead of using
/// arrival order. Anything that doesn't match that shape - Kanban
/// cards, to-dos, ordinary prose without a leading time - returns
/// null and leaves dedupeAndCheckAppend's original ours-then-theirs
/// order untouched. Only ever reorders whole paragraphs; never drops,
/// splits, or duplicates one.
String? chronologicallyOrderedIfJournal(String ours, String theirsRemaining) {
  final paras = [..._splitParagraphs(ours), ..._splitParagraphs(theirsRemaining)];
  if (paras.isEmpty || !paras.every((p) => _journalTimePattern.hasMatch(p))) {
    return null;
  }
  paras.sort((a, b) => int.parse(_journalTimePattern.firstMatch(a)!.group(1)!)
      .compareTo(int.parse(_journalTimePattern.firstMatch(b)!.group(1)!)));
  return paras.join('\n\n');
}

enum _LineOp { equal, baseOnly, otherOnly }

/// Same plain LCS diff word_diff.dart/line_diff.dart already use at
/// their own granularity, here over whole lines. [a] is always [base]
/// in mergeThreeWayLines below, [b] the other side - baseOnly means "in
/// base, gone from the other side" (a deletion/replacement), otherOnly
/// means "new in the other side, not in base" (an insertion).
List<(_LineOp, String)> _diffLines(List<String> a, List<String> b) {
  final n = a.length, m = b.length;
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      dp[i][j] = a[i] == b[j]
          ? dp[i + 1][j + 1] + 1
          : (dp[i + 1][j] > dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
    }
  }
  final result = <(_LineOp, String)>[];
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      result.add((_LineOp.equal, a[i]));
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      result.add((_LineOp.baseOnly, a[i]));
      i++;
    } else {
      result.add((_LineOp.otherOnly, b[j]));
      j++;
    }
  }
  while (i < n) {
    result.add((_LineOp.baseOnly, a[i]));
    i++;
  }
  while (j < m) {
    result.add((_LineOp.otherOnly, b[j]));
    j++;
  }
  return result;
}

/// 2026-09-06: real gap found live - a phone stuck behind on fetch
/// finally caught up and surfaced a genuine "ancestor but content
/// diverged" case (see sync_service.dart's remoteOid==baseOid branch)
/// on a real Kanban board, where both sides had only added different
/// list items in different sections - a plain, safe, non-overlapping
/// change on each side. That branch had no automatic-merge attempt at
/// all, only detect-then-back-up-and-ask, because a real git-level
/// three-way merge (Merge.trees()) can't be verified locally (git2dart's
/// bundled binaries are x86_64-only, this dev machine is arm64 - see
/// that branch's own long comment). This function sidesteps that
/// specific blocker: it's pure Dart string/list logic, no git2dart
/// calls, so - unlike the real git merge path - it's fully unit-testable
/// on this arm64 machine before ever touching a real device.
///
/// Diffs [ours] and [theirs] each against the real common ancestor
/// [base] (same LCS diff as dedupeAndCheckAppend's neighbors), then
/// merges the two edit scripts by walking [base]'s own line positions.
/// Where only one side touched a given base line, that side's edit wins
/// outright - not a conflict, since the other side made no competing
/// claim on that exact line. The one thing this refuses to guess at,
/// matching every other merge path in this app: if BOTH sides
/// independently touched the very same base line, that's a genuine
/// same-line collision (the exact failure class dedupeAndCheckAppend's
/// own history flagged as dangerous to silently paper over) - returns
/// null immediately, deferring to this app's existing backup-and-ask
/// flow rather than guessing which edit should win.
///
/// Pure insertions (new lines with no base counterpart) landing at the
/// same gap from both sides are NOT a collision - neither side is
/// overwriting content the other touched, so both are kept, ours first.
String? mergeThreeWayLines(String base, String ours, String theirs) {
  final baseLines = base.split('\n');
  final oursDiff = _diffLines(baseLines, ours.split('\n'));
  final theirsDiff = _diffLines(baseLines, theirs.split('\n'));

  final oursKept = List<bool>.filled(baseLines.length, true);
  final oursGapInserts =
      List.generate(baseLines.length + 1, (_) => <String>[]);
  _fillFromDiff(oursDiff, oursKept, oursGapInserts);

  final theirsKept = List<bool>.filled(baseLines.length, true);
  final theirsGapInserts =
      List.generate(baseLines.length + 1, (_) => <String>[]);
  _fillFromDiff(theirsDiff, theirsKept, theirsGapInserts);

  for (var k = 0; k < baseLines.length; k++) {
    if (!oursKept[k] && !theirsKept[k]) return null;
  }

  final out = StringBuffer();
  void writeGap(int g) {
    for (final l in oursGapInserts[g]) {
      out.write(l);
      out.write('\n');
    }
    for (final l in theirsGapInserts[g]) {
      out.write(l);
      out.write('\n');
    }
  }

  writeGap(0);
  for (var k = 0; k < baseLines.length; k++) {
    if (oursKept[k] && theirsKept[k]) {
      out.write(baseLines[k]);
      out.write('\n');
    }
    writeGap(k + 1);
  }
  final result = out.toString();
  return result.endsWith('\n')
      ? result.substring(0, result.length - 1)
      : result;
}

void _fillFromDiff(List<(_LineOp, String)> diff, List<bool> kept,
    List<List<String>> gapInserts) {
  var baseIdx = 0;
  for (final (op, text) in diff) {
    switch (op) {
      case _LineOp.equal:
        baseIdx++;
      case _LineOp.baseOnly:
        kept[baseIdx] = false;
        baseIdx++;
      case _LineOp.otherOnly:
        gapInserts[baseIdx].add(text);
    }
  }
}

// 2026-08-19: matches one already-wrapped callout header, at any quote
// depth (`>`, `> >`, `> > >`, ...) - extractStackedVersions strips
// depth first, so this only ever needs to match depth-0 headers.
//
// [-—] (accepts a regular dash OR an em dash) - real device finding,
// same night as the flatten fix: this file used to write an em dash,
// content already on a vault from before that got fixed to a regular
// dash is invisible to a parser that only recognizes the new
// character, silently skipping exactly the already-broken content this
// whole mechanism exists to repair. The write side (below) only ever
// produces a regular dash now - this stays permissive on read so
// older, already-written content is still recoverable.
final calloutHeaderPattern = RegExp(
  r'^\[!(?:info|warning)\]\+ SYNC CONFLICT [-—] (.+?) \(review and delete one[^)]*\)$',
  multiLine: true,
);

/// One version of a note's content as tracked through possibly several
/// rounds of unresolved conflicts on the same line.
typedef StackedVersion = ({String label, String body});

/// 2026-08-19: root cause of the "nested/compounding conflict markers"
/// bug found on real device - if a new conflict fires on content that
/// *already* contains an unresolved SYNC CONFLICT callout (the user
/// never actually resolved the last one), the old code wrapped the
/// whole thing - including its own nested callouts - in another layer
/// of `> ` quoting. Each unresolved round nested one level deeper, and
/// Obsidian only visually expands the outermost/last callout by
/// default, so older rounds became invisible even though their content
/// was still there, unresolved, in the raw file.
///
/// This strips all quote-prefix depth first (so a header buried under
/// `> > >` reads identically to one at depth 0), then splits on
/// callout headers to recover every previously-stacked version as a
/// flat list. A block with no header at all (the common case - ours
/// was never itself a conflict) comes back as a single synthetic
/// "yours" version, so callers don't need a separate first-time path.
List<StackedVersion> extractStackedVersions(String text) {
  final unquoted = text
      .split('\n')
      .map((l) => l.replaceFirst(RegExp(r'^(> ?)+'), ''))
      .join('\n');
  final headers = calloutHeaderPattern.allMatches(unquoted).toList();
  if (headers.isEmpty) {
    return [(label: 'yours', body: text.trim())];
  }
  final versions = <StackedVersion>[];
  for (var i = 0; i < headers.length; i++) {
    final bodyStart = headers[i].end + 1;
    final bodyEnd =
        i + 1 < headers.length ? headers[i + 1].start : unquoted.length;
    final body =
        bodyEnd > bodyStart ? unquoted.substring(bodyStart, bodyEnd).trim() : '';
    if (body.isEmpty) continue;
    versions.add((label: headers[i].group(1)!, body: body));
  }
  return versions.isEmpty ? [(label: 'yours', body: text.trim())] : versions;
}

String repairConflictMarkers(String content,
    {required String otherLabel, String? otherTime}) {
  final isKanban = kanbanFrontmatterPattern.hasMatch(content);

  String mergeBoth(Match m) {
    final ours = m.group(1)!.trim();
    final theirs = m.group(2)!.trim();

    if (normalizeWhitespace(ours) == normalizeWhitespace(theirs)) {
      return '$ours\n';
    }

    final appended = dedupeAndCheckAppend(ours, theirs);
    if (appended != null) return '$appended\n';

    if (isKanban) {
      final otherLines = theirs
          .split('\n')
          .map((l) => '%% CONFLICT-OTHER ($otherLabel): $l %%')
          .join('\n');
      return '$ours\n$otherLines\n';
    }
    // 2026-08-18: "yours" used to sit as bare unwrapped text right
    // before the callout - readable, but with no marker of its own,
    // there was no reliable way to tell where it started (could be a
    // whole paragraph or one word mid-sentence) when re-reading the
    // file later for the tap-to-pick conflict picker. Wrapping it in a
    // matching callout gives both sides the same clean, parseable
    // boundary conflict_scanner.dart needs - still just as readable by
    // eye in Obsidian, now two stacked callouts instead of prose+one.
    //
    // 2026-08-19: always flatten through extractStackedVersions first,
    // instead of wrapping `ours` directly - this is what stops nesting.
    // Whatever versions were already stacked inside `ours` (one, if it
    // was never itself a conflict; more, if it was) come back out as
    // siblings at the same quote depth as the new `theirs` version,
    // never nested one layer deeper. Every round after this one keeps
    // adding siblings, not depth.
    final theirsLabel =
        otherTime != null ? '$otherLabel - $otherTime' : otherLabel;
    final versions = [
      ...extractStackedVersions(ours),
      (label: theirsLabel, body: theirs),
    ];
    // 2026-09-07: real feedback, live - two versions that are actually
    // unrelated journal entries (this user's real convention: a bare
    // leading HHMM time, e.g. "0715 I left...") used to always show
    // "yours" first regardless of what time of day either happened,
    // since this list is built in arrival order, not time order. When
    // every version's body starts with that exact HHMM shape, sort the
    // versions chronologically before rendering - still two separate
    // callouts for the user to review and pick from, never silently
    // combined, just shown in the order the day actually happened. A
    // version with no leading time (ordinary prose, a Kanban card body)
    // leaves the whole list in its original arrival order untouched -
    // this never guesses.
    if (versions.every((v) => _journalTimePattern.hasMatch(v.body))) {
      versions.sort((a, b) =>
          int.parse(_journalTimePattern.firstMatch(a.body)!.group(1)!)
              .compareTo(
                  int.parse(_journalTimePattern.firstMatch(b.body)!.group(1)!)));
    }
    final blocks = <String>[];
    for (var i = 0; i < versions.length; i++) {
      final kind = i == 0 ? '!info' : '!warning';
      final callout =
          versions[i].body.split('\n').map((l) => '> $l\n').join('');
      blocks.add('> [$kind]+ SYNC CONFLICT - ${versions[i].label} '
          '(review and delete one)\n$callout');
    }
    return '${blocks.join('\n')}\n';
  }

  var fixed = content.replaceAllMapped(fullConflictPattern, mergeBoth);
  // Stray/incomplete markers left over from a previous failed repair.
  fixed = fixed.replaceAll(partialConflictPattern, '');
  return consolidateStackedRuns(fixed);
}

// 2026-08-19: real device finding, confirmed the same night as the
// flatten fix above - mergeBoth() only ever sees the text INSIDE one
// git conflict marker hunk. Git's hunk boundary is only as wide as the
// lines that actually differ between the two sides - if a user edits
// just the one body line inside an existing callout (not its header),
// git's hunk is exactly that one line, and the untouched header line
// above it - along with any other already-stacked callout further
// down the file - never passes through mergeBoth() at all. Confirmed
// on real device: this produced a duplicate "yours" header (the old
// untouched one, followed immediately by a fresh one mergeBoth() wrote
// for just the conflicting line) and stranded an older callout further
// down the file as if it were a separate, unrelated conflict - the
// picker showed 2 versions instead of the real 3, and the orphaned old
// header text leaked into a panel's body since the scanner's own
// parsing didn't expect a header with no body of its own.
//
// This is a second, whole-file pass run after the per-hunk replace
// above: it finds any run of 2+ directly-adjacent SYNC CONFLICT
// callouts - regardless of whether mergeBoth() ever saw them as one
// unit - and re-flattens that whole run through extractStackedVersions
// again. That function already discards any header with an empty body
// (exactly what an orphaned duplicate header looks like once
// extracted), so this cleanly collapses the duplicate away and
// recovers every real version, instead of leaving mergeBoth()'s
// narrower, hunk-scoped view as the final answer. Safe to run
// unconditionally: a file with no adjacency problem simply has nothing
// for this pattern to match, and re-flattening an already-canonical
// block is idempotent.
// [-—] - see calloutHeaderPattern's comment above: must recognize
// already-written em-dash content too, not just the current write
// format, or this whole consolidation pass silently skips it.
//
// 2026-08-19, later the same night: tried widening the trailing `\n?`
// to tolerate 2+ blank lines (a gap that appears between genuinely-
// stacked siblings of ONE accumulating conflict, as an artifact of
// older repair rounds) - but there is NO reliable way to tell "two
// blank lines because these are siblings of the same conflict" apart
// from "two blank lines because these are two completely different,
// unrelated conflicts that just happen to sit near each other in the
// document" - both shapes were observed in the same real test file,
// with identical formatting. Widening the tolerance fixed the first
// case but silently merged the second into one wrong combined list -
// a user picking a version could then discard content from a totally
// unrelated conflict without meaning to, which is worse than the
// original bug (an orphaned, still-readable, still-editable-by-hand
// leftover). Reverted to `\n?` (exactly one optional blank line) -
// this is what this app's own write template always produces between
// true siblings, so it's the correct signal to key on. **Known
// residual limitation**, not fixed: a conflict block separated from
// its true sibling by 2+ blank lines (only seen so far on legacy
// content from before this session's fixes) stays unconsolidated -
// cosmetically stale (may still show an old-format dash) but not
// unsafe: it's never silently merged with anything, and remains
// readable/hand-editable in the raw file either way.
final _stackedRunPattern = RegExp(
  r'(?:> \[!(?:info|warning)\]\+ SYNC CONFLICT [-—] .+? \(review and delete one[^)]*\)\n'
  r'(?:> .*\n?)*\n?){2,}',
);

String consolidateStackedRuns(String content) {
  return content.replaceAllMapped(_stackedRunPattern, (m) {
    final versions = extractStackedVersions(m.group(0)!);
    if (versions.length < 2) return m.group(0)!;
    final blocks = <String>[];
    for (var i = 0; i < versions.length; i++) {
      final kind = i == 0 ? '!info' : '!warning';
      final callout =
          versions[i].body.split('\n').map((l) => '> $l\n').join('');
      blocks.add('> [$kind]+ SYNC CONFLICT - ${versions[i].label} '
          '(review and delete one)\n$callout');
    }
    return '${blocks.join('\n')}\n';
  });
}
