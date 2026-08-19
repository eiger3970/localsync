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
    return '$ours\n\n${remaining.join('\n').trim()}';
  }
  return null;
}

// 2026-08-19: matches one already-wrapped callout header, at any quote
// depth (`>`, `> >`, `> > >`, ...) - extractStackedVersions strips
// depth first, so this only ever needs to match depth-0 headers.
final calloutHeaderPattern = RegExp(
  r'^\[!(?:info|warning)\]\+ SYNC CONFLICT - (.+?) \(review and delete one[^)]*\)$',
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
final _stackedRunPattern = RegExp(
  r'(?:> \[!(?:info|warning)\]\+ SYNC CONFLICT - .+? \(review and delete one[^)]*\)\n'
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
