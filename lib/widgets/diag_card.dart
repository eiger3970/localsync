// widgets/diag_card.dart
//
// 2026-08-20: "show error in human language, how to fix it, then the
// error code verbose details - you've done this format with some
// errors but not others" - this was a private class inside
// linking_screen.dart's _FailedView (setup-flow failures); extracted
// here so home_screen.dart's sync-error dialog can use the exact same
// labeled-card layout instead of dumping one undifferentiated block of
// text, which was the actual inconsistency being reported.

import 'package:flutter/material.dart';
import '../theme.dart';

class DiagCard extends StatelessWidget {
  final String label;
  final String text;
  final Color accent;
  // Raw exception text has no natural length limit - unlike the
  // human-written WHAT HAPPENED/HOW TO FIX IT strings, it can run long
  // enough to push the rest of the screen (including a drag canvas)
  // mostly off-screen. Left null for those short, hand-written strings.
  final int? maxLength;
  // 2026-08-21: real feedback, live - "check all text which is
  // verbose, change to point form" + "add an appropriate small image
  // to the left." [icon] labels the card's purpose at a glance
  // (WHAT HAPPENED/RAW ERROR don't need one, HOW TO FIX IT does -
  // caller's choice, not forced here). [bulleted] renders each of the
  // resolution strings' existing `\n`-separated lines (already one
  // point per line, per the 2026-08-19 convention noted where these
  // strings are written) as a real bulleted list instead of one flat
  // paragraph - the content was already structured as points, DiagCard
  // just wasn't presenting it that way.
  final IconData? icon;
  final bool bulleted;
  const DiagCard({
    super.key,
    required this.label,
    required this.text,
    required this.accent,
    this.maxLength,
    this.icon,
    this.bulleted = false,
  });

  // 2026-08-23: real feedback, live - "can you have this terminal text
  // in a different font type... this mixes up with the following text."
  // Backtick-delimited spans (`sudo systemctl status ssh`) render in a
  // monospace font, everything else stays the normal body style - a
  // simple inline convention rather than a new field per string, since
  // several resolution strings already embed real commands.
  List<InlineSpan> _parseInlineCode(String line, TextStyle base) {
    final monospace = base.copyWith(fontFamily: 'monospace', color: kGreen);
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'`([^`]+)`');
    var last = 0;
    for (final match in pattern.allMatches(line)) {
      if (match.start > last) {
        spans.add(
            TextSpan(text: line.substring(last, match.start), style: base));
      }
      spans.add(TextSpan(text: match.group(1), style: monospace));
      last = match.end;
    }
    if (last < line.length) {
      spans.add(TextSpan(text: line.substring(last), style: base));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final displayText = maxLength != null && text.length > maxLength!
        ? '${text.substring(0, maxLength!)}…'
        : text;
    final bodyStyle = TextStyle(color: kStar, fontSize: 15, height: 1.7);
    // 2026-08-23: real feedback, live - "should the user work through
    // all 5 points now or just point 1 and test... this is confusing."
    // A numbered fix list never said how to use it. Added once here
    // (not per resolution string) so every numbered fix list in the
    // app gets this for free - only shown when every line is actually
    // numbered, not for plain bulleted content with no real sequence.
    final lines =
        displayText.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final isNumberedList = bulleted &&
        lines.isNotEmpty &&
        lines.every((l) => RegExp(r'^\d+\.\s').hasMatch(l));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurface,
        border: Border(left: BorderSide(color: accent, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: accent, size: 15),
                const SizedBox(width: 6),
              ],
              Text(label,
                  style: TextStyle(
                      color: accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5)),
            ],
          ),
          const SizedBox(height: 8),
          if (isNumberedList) ...[
            // 2026-08-25: real feedback, live - "text too dark and
            // small." kTextMid/12px -> kStar/13px, matching this app's
            // other secondary-text consolidation pass
            // (linking_screen.dart's Stage 1 intro block, same day) -
            // italic alone is enough to read as a meta-note without
            // also being harder to read than the content it's next to.
            Text(
                'Try step 1 first, retest, then move to the next only if needed.',
                style: TextStyle(
                    color: kStar, fontSize: 13, fontStyle: FontStyle.italic)),
            const SizedBox(height: 8),
          ],
          if (bulleted)
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // A handful of resolution strings are already
                    // numbered steps ("1. ...", "2. ..."), which read
                    // as a list on their own - a "•" in front would
                    // just double-mark those. Only bullet a line that
                    // isn't already leading with its own number.
                    SizedBox(
                      width: 16,
                      child: Text(RegExp(r'^\d+\.\s').hasMatch(line) ? '' : '•',
                          style: TextStyle(
                              color: kStar, fontSize: 15, height: 1.7)),
                    ),
                    Expanded(
                      child: Text.rich(TextSpan(
                          children: _parseInlineCode(line, bodyStyle))),
                    ),
                  ],
                ),
              )
          else
            Text.rich(
                TextSpan(children: _parseInlineCode(displayText, bodyStyle))),
        ],
      ),
    );
  }
}
