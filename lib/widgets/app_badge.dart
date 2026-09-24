// widgets/app_badge.dart
//
// 2026-09-24: real feedback, live - "you always forget the human
// perspective, rotating and swapping frequently from desktop to phone
// to app, needs context for humans using new things... users need this
// context too." Setup steps jump between LocalSync, Obsidian, the Files
// picker and the phone itself (app switcher) inside ONE checklist, and
// nothing said which app a step happens in. Every step string can now
// start with a tag - "@localsync ", "@obsidian ", "@files ", "@phone " -
// shown as a small coloured badge before the text.

import 'package:flutter/material.dart';
import '../theme.dart';

enum StepApp { phone, localsync, obsidian, files }

/// Splits a tagged step ("@obsidian tap Create") into its app and text.
(StepApp?, String) splitStepApp(String step) {
  for (final app in StepApp.values) {
    final tag = '@${app.name} ';
    if (step.startsWith(tag)) return (app, step.substring(tag.length));
  }
  return (null, step);
}

class AppBadge extends StatelessWidget {
  final StepApp app;
  const AppBadge(this.app, {super.key});

  static const _obsidianPurple = Color(0xFFA78BFA);
  static const _filesBlue = Color(0xFF1E88E5);

  static (String, IconData, Color) look(StepApp a) => switch (a) {
        StepApp.phone => ('PHONE', Icons.phone_iphone, kTextMid),
        StepApp.localsync => ('LOCALSYNC', Icons.sync, kGreen),
        StepApp.obsidian => (
            'OBSIDIAN',
            Icons.diamond_outlined,
            _obsidianPurple
          ),
        StepApp.files => ('FILES', Icons.folder, _filesBlue),
      };

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = look(app);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.7)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8)),
      ]),
    );
  }
}

/// The app to badge on step [i]: its own app when it differs from the
/// step before, else null (same app, no repeat badge).
StepApp? badgeFor(List<String> steps, int i) {
  final app = splitStepApp(steps[i]).$1;
  if (app == null) return null;
  if (i > 0 && splitStepApp(steps[i - 1]).$1 == app) return null;
  return app;
}
