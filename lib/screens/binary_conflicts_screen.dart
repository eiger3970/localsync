// screens/binary_conflicts_screen.dart
//
// 2026-08-27: real gap found and fixed (sync_service.dart's
// repairBinaryConflictsOnDisk) - a genuine git conflict on any
// non-markdown file (images/PDFs in an existing vault, or literally any
// file in a Tier 0 generic-sync repo) used to fall through with no
// backup and no visibility at all. The fix backs up both sides and
// auto-keeps "ours" as a safe default - this screen is what turns that
// safe default into a real choice, same idea as conflict_scanner.dart's
// undoReferenceCallout for markdown, just for whole files. Deliberately
// its own screen, not folded into ConflictsScreen's own ListView - see
// that screen's own comment on why (fragile section index math).

import 'package:flutter/material.dart';
import '../theme.dart';
import '../models/repository.dart';
import '../services/binary_conflict_log.dart';
import '../services/vault_folder_service.dart';

class BinaryConflictsScreen extends StatefulWidget {
  final Repository repo;
  const BinaryConflictsScreen({super.key, required this.repo});

  @override
  State<BinaryConflictsScreen> createState() => _BinaryConflictsScreenState();
}

class _BinaryConflictsScreenState extends State<BinaryConflictsScreen> {
  final _vaultFolder = VaultFolderService();
  late Future<List<BinaryConflictLogEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = _scan();
  }

  Future<List<BinaryConflictLogEntry>> _scan() async {
    final path = await _vaultFolder.startAccessing(widget.repo.vaultBookmark);
    if (path == null) return [];
    try {
      return scanBinaryConflictLog(path);
    } finally {
      await _vaultFolder.stopAccessing(widget.repo.vaultBookmark);
    }
  }

  Future<void> _swap(BinaryConflictLogEntry entry) async {
    final path = await _vaultFolder.startAccessing(widget.repo.vaultBookmark);
    if (path == null) return;
    try {
      swapBinaryConflict(path, entry);
    } finally {
      await _vaultFolder.stopAccessing(widget.repo.vaultBookmark);
    }
    if (mounted) setState(() => _future = _scan());
  }

  Future<void> _dismiss(BinaryConflictLogEntry entry) async {
    final path = await _vaultFolder.startAccessing(widget.repo.vaultBookmark);
    if (path == null) return;
    try {
      dismissBinaryConflictLogEntry(path, entry);
    } finally {
      await _vaultFolder.stopAccessing(widget.repo.vaultBookmark);
    }
    if (mounted) setState(() => _future = _scan());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kVoid,
        title: Text('Whole-file conflicts', style: TextStyle(color: kStar)),
      ),
      body: FutureBuilder<List<BinaryConflictLogEntry>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = snapshot.data ?? const [];
          if (entries.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'No whole-file conflicts pending review.',
                  style: TextStyle(color: kTextMid, fontSize: 15),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _BinaryConflictTile(
              entry: entries[i],
              onSwap: () => _swap(entries[i]),
              onDismiss: () => _dismiss(entries[i]),
            ),
          );
        },
      ),
    );
  }
}

class _BinaryConflictTile extends StatelessWidget {
  final BinaryConflictLogEntry entry;
  final VoidCallback onSwap;
  final VoidCallback onDismiss;
  const _BinaryConflictTile({
    required this.entry,
    required this.onSwap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurface,
        border: Border(left: BorderSide(color: kTextDim, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(entry.path,
              style: TextStyle(
                  color: kStar, fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            'Both versions saved. Currently keeping your version - '
            "${entry.otherLabel}'s edit from ${entry.when} is the other "
            'option.',
            style: TextStyle(color: kTextMid, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onSwap,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: kGreen),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: Text('USE ${entry.otherLabel.toUpperCase()}\'S VERSION',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: kGreen,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: onDismiss,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: kTextDim),
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                ),
                child: Text('KEEP MINE',
                    style: TextStyle(
                        color: kTextMid,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
