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
            // Alphabetical: add, change, remove - per house naming rule.
            if (r.filesAdded > 0) _Bullet('add ${r.filesAdded} file${r.filesAdded == 1 ? '' : 's'}'),
            if (r.filesModified > 0) _Bullet('change ${r.filesModified} file${r.filesModified == 1 ? '' : 's'}'),
            if (r.filesRemoved > 0) _Bullet('remove ${r.filesRemoved} file${r.filesRemoved == 1 ? '' : 's'}'),
            const SizedBox(height: 8),
            if (!_showDetails)
              TextButton.icon(
                onPressed: () => setState(() => _showDetails = true),
                icon: const Icon(Icons.list, color: kStar, size: 18),
                label: const Text('Details',
                    style: TextStyle(color: kStar, fontSize: 15)),
              )
            else
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: SingleChildScrollView(
                    child: _FileList(result: r),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        // "Not now"/"Continue" -> action verbs: what will actually
        // happen if you tap it, not a generic yes/no.
        TextButton.icon(
          onPressed: () => Navigator.pop(context, false),
          icon: const Icon(Icons.close, color: kTextDim, size: 18),
          label: const Text("Don't sync",
              style: TextStyle(color: kTextDim, fontSize: 15)),
        ),
        TextButton.icon(
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.sync, color: kGreen, size: 18),
          label: const Text('Sync',
              style: TextStyle(color: kGreen, fontSize: 15)),
        ),
      ],
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
