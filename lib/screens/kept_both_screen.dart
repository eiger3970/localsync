// screens/kept_both_screen.dart
//
// 2026-09-08: real feedback, live - "one tap" Undo for Keep Both, not
// just "Keep this version." Deliberately its own screen, not folded
// into ConflictsScreen's own ListView - same reasoning as
// binary_conflicts_screen.dart's own comment (fragile section index
// math already, a fourth interleaved section makes it worse).

import 'package:flutter/material.dart';
import '../theme.dart';
import '../models/repository.dart';
import '../services/conflict_scanner.dart';
import '../services/vault_folder_service.dart';

class KeptBothScreen extends StatefulWidget {
  final Repository repo;
  const KeptBothScreen({super.key, required this.repo});

  @override
  State<KeptBothScreen> createState() => _KeptBothScreenState();
}

class _KeptBothScreenState extends State<KeptBothScreen> {
  final _vaultFolder = VaultFolderService();
  late Future<List<KeptBothEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = _scan();
  }

  Future<List<KeptBothEntry>> _scan() async {
    final path = await _vaultFolder.startAccessing(widget.repo.vaultBookmark);
    if (path == null) return [];
    try {
      return scanForKeptBoth(path);
    } finally {
      await _vaultFolder.stopAccessing(widget.repo.vaultBookmark);
    }
  }

  Future<void> _undo(KeptBothEntry entry) async {
    final path = await _vaultFolder.startAccessing(widget.repo.vaultBookmark);
    if (path == null) return;
    try {
      await undoKeepBoth(path, entry);
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
        title: Text('Merged conflicts', style: TextStyle(color: kStar)),
      ),
      body: FutureBuilder<List<KeptBothEntry>>(
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
                  'No merged conflicts to undo.',
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
            itemBuilder: (context, i) => _KeptBothTile(
              entry: entries[i],
              onUndo: () => _undo(entries[i]),
            ),
          );
        },
      ),
    );
  }
}

class _KeptBothTile extends StatelessWidget {
  final KeptBothEntry entry;
  final VoidCallback onUndo;
  const _KeptBothTile({required this.entry, required this.onUndo});

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
          Text(entry.filePath,
              style: TextStyle(
                  color: kStar, fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            '${entry.versions.length} versions merged into this note as '
            'plain text.',
            style: TextStyle(color: kTextMid, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onUndo,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: kGreen),
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
            icon: Icon(Icons.undo, color: kGreen, size: 16),
            label: Text('UNDO - MAKE THIS AN ACTIVE CONFLICT AGAIN',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: kGreen, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
