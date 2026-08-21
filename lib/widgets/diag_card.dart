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

  @override
  Widget build(BuildContext context) {
    final displayText = maxLength != null && text.length > maxLength!
        ? '${text.substring(0, maxLength!)}…'
        : text;
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
          if (bulleted)
            for (final line in displayText.split('\n').where((l) => l.trim().isNotEmpty))
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
                      child: Text(
                          RegExp(r'^\d+\.\s').hasMatch(line) ? '' : '•',
                          style: TextStyle(
                              color: kStar, fontSize: 15, height: 1.7)),
                    ),
                    Expanded(
                      child: Text(line,
                          style: TextStyle(
                              color: kStar, fontSize: 15, height: 1.7)),
                    ),
                  ],
                ),
              )
          else
            Text(displayText,
                style: TextStyle(color: kStar, fontSize: 15, height: 1.7)),
        ],
      ),
    );
  }
}
