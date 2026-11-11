// services/conflict_table.dart
//
// 2026-11-11: real ask - Obsidian's blue/orange SYNC CONFLICT boxes are
// "foreign and meaningless"; the desktop must show the same left/right rows
// the phone's conflict picker shows. This renders the picker's own hunks
// (line_diff.dart mergeHunks) as a two-column markdown table: identical text
// in both cells of one row, a one-sided paragraph with an empty cell opposite.
// Pure string transform. NOT yet wired into any writer or parser.

import 'line_diff.dart';

String _cell(String s) =>
    s.trim().replaceAll('|', r'\|').replaceAll(RegExp(r'\n{2,}'), '<br><br>').replaceAll('\n', '<br>');

/// Two-column table for [ours] (left) vs [theirs] (right), rows in the same
/// order as the picker. Returns '' when the texts are identical.
String conflictTable(String ours, String theirs,
    {String leftLabel = 'Phone', String rightLabel = 'Desktop'}) {
  if (ours.trim() == theirs.trim()) return '';
  final hunks = mergeHunks(ours, theirs);
  final b = StringBuffer('| $leftLabel | $rightLabel |\n|---|---|\n');
  for (final h in hunks) {
    final l = _cell(h.ours);
    final r = h.op == HunkOp.same ? l : _cell(h.theirs);
    if (l.isEmpty && r.isEmpty) continue;
    b.writeln('| $l | $r |');
  }
  return b.toString();
}
