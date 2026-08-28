// widgets/git_install_consent.dart
//
// 2026-08-28: real feedback, live - "normies need to be 100% informed"
// before pairing_controller.dart's auto `sudo apt-get install git` step
// ever runs, using the desktop password with zero disclosure until this.
// Shown before every real pairing attempt - a security consent, not a
// convenience prompt, so per explicit direction (2026-08-28, follow-up,
// after the remembered-choice version read as confusing/buggy on a real
// device) this is never persisted or skipped based on a prior answer.
// Explicit per direction: warn against blindly trusting any app with a
// password, show the literal command rather than a vague description,
// and give a real manual-install choice alongside the automatic one,
// not just an accept/decline on automation.
//
// Returns true (let LocalSync install it), false (I'll install it
// myself), or null (cancelled - caller should not proceed with pairing
// at all, this is a real decision point, not a dismissible nag).

import 'package:flutter/material.dart';
import '../theme.dart';

Future<bool?> showGitInstallConsent(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _GitInstallConsentDialog(),
  );
}

class _GitInstallConsentDialog extends StatefulWidget {
  const _GitInstallConsentDialog();

  @override
  State<_GitInstallConsentDialog> createState() =>
      _GitInstallConsentDialogState();
}

class _GitInstallConsentDialogState extends State<_GitInstallConsentDialog> {
  bool _showCommand = false;

  static const _warnLines = [
    (Icons.verified_user_outlined, 'Only for apps you already trust'),
    (Icons.lock_outline, 'Never leaves this device'),
    (Icons.block, 'Never stored, anywhere'),
  ];

  static const _infoLines = [
    (Icons.desktop_windows_outlined, 'Debian/Linux only - not Mac or Windows'),
    (Icons.looks_one_outlined, 'Runs once, only if git is missing'),
    (Icons.vpn_key_outlined, 'Uses sudo, with this same password'),
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: kSurface,
      title: Text('Before you type your password',
          style: TextStyle(color: kStar, fontSize: 17, fontWeight: FontWeight.w700)),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.amber, width: 1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (icon, text) in _warnLines) ...[
                    _ConsentLine(
                        icon: icon, text: text, iconColor: Colors.amber, color: kStar),
                    if (text != _warnLines.last.$2) const SizedBox(height: 6),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            for (final (icon, text) in _infoLines) ...[
              _ConsentLine(icon: icon, text: text, iconColor: kGreen, color: kTextMid),
              if (text != _infoLines.last.$2) const SizedBox(height: 8),
            ],
            const SizedBox(height: 12),
            InkWell(
              onTap: () => setState(() => _showCommand = !_showCommand),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 2026-08-28: real feedback, live - "arrow points down
                  // but should point right. Command showing has arrow
                  // pointing up but should point down." Collapsed = right
                  // (there's more to reveal to the right/below), expanded
                  // = down (pointing at the command box that just opened
                  // directly beneath it) - was backwards (expand_more/
                  // expand_less, an up/down pair with no "collapsed"
                  // state at all).
                  Icon(_showCommand ? Icons.keyboard_arrow_down : Icons.chevron_right,
                      color: kGreen, size: 18),
                  const SizedBox(width: 4),
                  Text('Show the exact command',
                      style: TextStyle(
                          color: kGreen, fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            if (_showCommand) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kVoid,
                  border: Border.all(color: kBorder),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('sudo apt-get install -y git',
                    style: TextStyle(
                        color: kStar, fontSize: 13, fontFamily: 'monospace')),
              ),
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      actions: [
        // 2026-08-28: real feedback, live - "the button is cut off the
        // right edge of the phone screen." The old two-button Row inside
        // AlertDialog's actions overflowed the dialog's real width on a
        // real device. Stacked full-width instead - guaranteed to fit
        // regardless of text length or screen width, not just a shorter-
        // text bet that could overflow again on a narrower phone.
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: kGreen),
              child: Text('LocalSync auto install',
                  style: TextStyle(color: kVoid, fontSize: 14, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              style: OutlinedButton.styleFrom(side: BorderSide(color: kBorder)),
              child: Text('Install git myself',
                  style: TextStyle(color: kTextMid, fontSize: 14)),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: Text('Cancel', style: TextStyle(color: kTextDim)),
            ),
          ],
        ),
      ],
    );
  }
}

// 2026-08-28: real feedback, live - "verbose, KISS, use point form and
// images" - both bullet groups above were two dense paragraphs; this is
// the shared icon+line row that replaced them, one glance per line
// instead of a sentence to parse.
class _ConsentLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color iconColor;
  final Color color;
  const _ConsentLine({
    required this.icon,
    required this.text,
    required this.iconColor,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(color: color, fontSize: 13, height: 1.3)),
        ),
      ],
    );
  }
}
