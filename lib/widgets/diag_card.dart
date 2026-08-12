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
  const DiagCard({
    super.key,
    required this.label,
    required this.text,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
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
          Text(text,
              style: const TextStyle(color: kStar, fontSize: 15, height: 1.7)),
        ],
      ),
    );
  }
}
