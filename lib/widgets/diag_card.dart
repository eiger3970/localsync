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
  const DiagCard({
    super.key,
    required this.label,
    required this.text,
    required this.accent,
    this.maxLength,
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
          Text(label,
              style: TextStyle(
                  color: accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5)),
          const SizedBox(height: 8),
          Text(displayText,
              style: const TextStyle(color: kStar, fontSize: 15, height: 1.7)),
        ],
      ),
    );
  }
}
