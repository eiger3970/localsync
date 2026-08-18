// widgets/sync_confirm_dialog.dart
//
// 2026-08-18: shown before a pull/push that would remove a large chunk
// of existing content - see SyncNeedsConfirmation in sync_service.dart
// for why this exists. Default view is a short bulleted "this sync
// will:" list; a "Details" toggle reveals the actual file list on
// request rather than always showing it (keeps the common case a quick
// glance, not a wall of text).
//
// 2026-08-18, real-device feedback: never had explicit dark-theme
// styling at all (unlike every other dialog in this app), rendering
// against Flutter's default AlertDialog theme instead of kSurface/kStar
// - "too small and dark to read" was a real bug, not a preference.
// Restyled to match every other dialog. Also restructured per direct
// feedback: no "Continue?" in the body (redundant with the Sync
// button), a real bulleted list instead of a run-on sentence, in
// alphabetical order (add/change/remove), and action-verb button
// labels (Details/Don't sync/Sync) instead of
// Show-details/Not-now/Continue.
//
// One shared widget, not copied per screen (home screen's gesture zone
// and the commit screen's typed-message push both need this) - same
// reasoning as sync_service.dart's own syncResultMessage().

import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/sync_service.dart';

Future<bool?> showSyncConfirmDialog(
  BuildContext context,
  SyncNeedsConfirmation result,
) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => _SyncConfirmDialog(result: result),
  );
}

class _SyncConfirmDialog extends StatefulWidget {
  final SyncNeedsConfirmation result;
  const _SyncConfirmDialog({required this.result});

  @override
  State<_SyncConfirmDialog> createState() => _SyncConfirmDialogState();
}

class _SyncConfirmDialogState extends State<_SyncConfirmDialog> {
  bool _showDetails = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    return AlertDialog(
      backgroundColor: kSurface,
      title: const Text('This sync will:',
          style: TextStyle(color: kStar, fontSize: 17)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 2026-08-18: this block (the bullets) must never move or
            // resize when Details is toggled - real-device feedback was
            // exactly this, the original text visibly shifting. It's
            // now structurally isolated from _showDetails: nothing
            // below this point can affect its size, since the details
            // area right below has a FIXED height always, whether
            // showing the file list or empty - the dialog's total
            // height never changes, so nothing above ever moves.
            // Alphabetical: add, change, remove - per house naming rule.
            if (r.filesAdded > 0) _Bullet('add ${r.filesAdded} file${r.filesAdded == 1 ? '' : 's'}'),
            if (r.filesModified > 0) _Bullet('change ${r.filesModified} file${r.filesModified == 1 ? '' : 's'}'),
            if (r.filesRemoved > 0) _Bullet('remove ${r.filesRemoved} file${r.filesRemoved == 1 ? '' : 's'}'),
            const SizedBox(height: 8),
            SizedBox(
              height: 160,
              child: _showDetails
                  ? SingleChildScrollView(child: _FileList(result: r))
                  : const Align(
                      alignment: Alignment.topLeft,
                      child: Text('Tap Details below to see the file list.',
                          style: TextStyle(color: kTextDim, fontSize: 13)),
                    ),
            ),
          ],
        ),
      ),
      // 2026-08-18: AlertDialog's default actions row (OverflowBar) can
      // wrap to vertical when three icon+label buttons don't fit -
      // that's exactly what happened. A plain Row with Expanded on each
      // button forces one horizontal row always, shrinking button
      // content to fit rather than ever stacking.
      actions: [
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                icon: Icons.list,
                label: 'Details',
                color: kStar,
                onPressed: () => setState(() => _showDetails = !_showDetails),
              ),
            ),
            Expanded(
              child: _ActionButton(
                icon: Icons.close,
                label: "Don't sync",
                color: Colors.redAccent,
                onPressed: () => Navigator.pop(context, false),
              ),
            ),
            Expanded(
              child: _ActionButton(
                icon: Icons.sync,
                label: 'Sync',
                color: kGreen,
                onPressed: () => Navigator.pop(context, true),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  ', style: TextStyle(color: kStar, fontSize: 16)),
          Expanded(
            child: Text(text, style: const TextStyle(color: kStar, fontSize: 16)),
          ),
        ],
      ),
    );
  }
}

class _FileList extends StatelessWidget {
  final SyncNeedsConfirmation result;
  const _FileList({required this.result});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      ...result.addedFiles.map((f) => _FileRow('+', f, kGreen)),
      ...result.modifiedFiles.map((f) => _FileRow('~', f, Colors.orange)),
      ...result.removedFiles.map((f) => _FileRow('-', f, Colors.redAccent)),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }
}

class _FileRow extends StatelessWidget {
  final String symbol;
  final String path;
  final Color  color;
  const _FileRow(this.symbol, this.path, this.color);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(
            text: '$symbol ',
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
          TextSpan(text: path, style: const TextStyle(color: kStar)),
        ]),
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      ),
    );
  }
}
