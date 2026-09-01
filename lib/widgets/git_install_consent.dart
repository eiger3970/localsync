// widgets/git_install_consent.dart
//
// 2026-08-28: real feedback, live - "normies need to be 100% informed"
// before pairing_controller.dart's auto `sudo apt-get install git` step
// ever runs, using the desktop password with zero disclosure until this.
// Explicit per direction: warn against blindly trusting any app with a
// password, show the literal command rather than a vague description,
// and give a real manual-install choice alongside the automatic one.
//
// 2026-09-01: real feedback, live - "if users see that, they'll have a
// heart attack... just a single button click." Real tension with the
// 2026-08-28 direction above (more disclosure, not less) - resolved by
// keeping everything that was there, just not all visible by default.
// One reassuring primary action now; the amber "only trust apps you
// trust" warning (read as alarming applied to this app itself, not
// informative) is gone entirely, and the info lines + exact command
// are still present but tucked behind an optional "Details" toggle
// instead of confronting every user by default.
//
// Returns true (let LocalSync install it), false (I'll install it
// myself), or null (cancelled - caller should not proceed with pairing
// at all, this is a real decision point, not a dismissible nag).

import 'package:flutter/material.dart';
import '../theme.dart';

Future<bool?> showGitInstallConsent(BuildContext context) {
  return showDialog<bool>(
    context: context,
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
  bool _showDetails = false;

  static const _infoLines = [
    (Icons.desktop_windows_outlined, 'Debian/Linux only - not Mac or Windows'),
    (Icons.looks_one_outlined, 'Runs once, only if git is missing'),
    (Icons.vpn_key_outlined, 'Uses sudo, with this same password'),
  ];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: kSurface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Setting up your desktop',
                style: TextStyle(
                    color: kStar, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Text(
              'LocalSync needs git on your desktop to sync your notes - '
              'it can install it automatically now, takes a few seconds.',
              style: TextStyle(color: kTextMid, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: kGreen),
              child: Text('Continue',
                  style: TextStyle(
                      color: kVoid, fontSize: 14, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => setState(() => _showDetails = !_showDetails),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                      _showDetails
                          ? Icons.keyboard_arrow_down
                          : Icons.chevron_right,
                      color: kTextMid,
                      size: 18),
                  const SizedBox(width: 4),
                  Text('Details',
                      style: TextStyle(color: kTextMid, fontSize: 13)),
                ],
              ),
            ),
            if (_showDetails) ...[
              const SizedBox(height: 8),
              for (final (icon, text) in _infoLines) ...[
                _ConsentLine(icon: icon, text: text, color: kTextMid),
                if (text != _infoLines.last.$2) const SizedBox(height: 8),
              ],
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
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('I\'ll install it myself instead',
                    style: TextStyle(color: kTextDim, fontSize: 13)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConsentLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _ConsentLine({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: kGreen, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: TextStyle(color: color, fontSize: 13, height: 1.3)),
        ),
      ],
    );
  }
}
