// widgets/sync_confirm_dialog.dart
//
// 2026-08-18: shown before a pull/push that would remove a large chunk
// of existing content - see SyncNeedsConfirmation in sync_service.dart
// for why this exists. Default view is the one-line plain-language
// summary; "sometimes users need to know more than a number", so a
// "Show details" toggle reveals the actual file list on request rather
// than always showing it (keeps the common case a quick glance, not a
// wall of text).
//
// One shared widget, not copied per screen (home screen's gesture zone
// and the commit screen's typed-message push both need this) - same
// reasoning as sync_service.dart's own syncResultMessage().

import 'package:flutter/material.dart';
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
      title: const Text('Confirm sync'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.summary),
            if (!_showDetails)
              TextButton(
                onPressed: () => setState(() => _showDetails = true),
                child: const Text('Show details'),
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
        // 2026-08-18: "Cancel" reads as a decision itself (rejecting the
        // sync) - for someone who isn't a git person, being forced to
        // decide "yes wipe it" or "no cancel it" in the moment is the
        // stressful part. "Not now" is the same no-op underneath -
        // nothing happens, the same prompt reappears next sync attempt
        // - but it reads as "I'll deal with this later", not a verdict.
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Not now'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

class _FileList extends StatelessWidget {
  final SyncNeedsConfirmation result;
  const _FileList({required this.result});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      ...result.removedFiles.map((f) => _FileRow('-', f, Colors.red)),
      ...result.addedFiles.map((f) => _FileRow('+', f, Colors.green)),
      ...result.modifiedFiles.map((f) => _FileRow('~', f, Colors.orange)),
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
          TextSpan(text: path),
        ]),
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
    );
  }
}
