// screens/backups_screen.dart
//
// 2026-09-29: Ken - Backups: every LocalSync safety-copy folder with its
// file count and size. Approved from the HTML preview the same day.
// 2026-09-30: Ken - "This means nothing to me. What backups? The whole
// vault, the what? Why are these backed up? Have a delete all option."
// Rows now say what each copy is and why it exists, in plain words; each
// row has a bin, and one Delete all clears the lot.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/repository.dart';
import '../services/localsync_cleanup.dart';
import 'backup_compare_screen.dart';
import '../services/repository_provider.dart';
import '../theme.dart';

class BackupsScreen extends StatefulWidget {
  final Repository repo;
  // Preview tests only: skip reading the folder.
  @visibleForTesting
  final List<BackupFolder>? previewFolders;
  const BackupsScreen({super.key, required this.repo, this.previewFolders});

  @override
  State<BackupsScreen> createState() => _BackupsScreenState();
}

class _BackupsScreenState extends State<BackupsScreen> {
  List<BackupFolder>? _folders;
  String? _error;
  bool _busy = false;

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul',
      'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  void initState() {
    super.initState();
    if (widget.previewFolders != null) {
      _folders = widget.previewFolders;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final f = await context
          .read<RepositoryProvider>()
          .withRepoFolder(widget.repo, (path) => listBackupFolders(path));
      if (mounted) setState(() => _folders = f ?? []);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  String get _things =>
      widget.repo.syncMode == SyncMode.genericFolder ? 'files' : 'notes';

  // What the copy is, and why LocalSync made it.
  (String, String) _describe(BackupFolder f) {
    final date = fullBackupDate(f.name);
    if (date != null) {
      return (
        'Copy of all your $_things, ${date.day} ${_months[date.month - 1]}',
        'Made when this phone was linked, in case the link went wrong'
      );
    }
    if (f.name == 'Conflict Backups') {
      return ('Old versions of $_things', 'Saved before each conflict fix');
    }
    final before = RegExp(r'^Conflict Backups before (.+)$').firstMatch(f.name);
    if (before != null) {
      return ('Older versions of $_things', 'Conflict fixes before ${before.group(1)}');
    }
    return (f.name, 'LocalSync safety copy');
  }

  Future<bool> _confirm(String title, int bytes) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: kSurface,
          title: Text(title, style: TextStyle(color: kStar, fontSize: 17)),
          content: Text(
              'Frees ${formatBytes(bytes)}. Your $_things are not touched.',
              style: TextStyle(color: kTextMid, fontSize: 14.5, height: 1.45)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text('CANCEL', style: TextStyle(color: kTextDim))),
            TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text('DELETE',
                    style: TextStyle(
                        color: Colors.redAccent, fontWeight: FontWeight.w700))),
          ],
        ),
      ) ==
      true;

  Future<void> _delete(List<BackupFolder> folders, String title) async {
    final bytes = folders.fold(0, (sum, f) => sum + f.bytes);
    if (!await _confirm(title, bytes) || !mounted) return;
    final provider = context.read<RepositoryProvider>();
    setState(() => _busy = true);
    try {
      await provider.withRepoFolder(
          widget.repo, (path) => deleteBackupFolders(path, folders));
      // Backups from before 2026-09-30 could still be in the synced
      // LocalSync folder - send the removal so the desktop drops them too.
      final synced = folders.any((f) => !f.relPath.startsWith('.'));
      final id = widget.repo.id;
      if (synced && id != null) {
        await provider.pushRepository(id,
            commitMessage: 'Delete LocalSync backups', confirmed: true);
      }
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _row(BackupFolder f) {
    final (title, why) = _describe(f);
    final opens = f.name == 'Conflict Backups';
    final body = Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: kBorder))),
      child: Row(children: [
        Icon(Icons.folder_outlined, color: kTextMid, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: kStar, fontSize: 15, fontWeight: FontWeight.w600)),
              Text('$why · ${formatBytes(f.bytes)}',
                  style: TextStyle(color: kTextDim, fontSize: 12.5)),
            ],
          ),
        ),
        if (opens) Icon(Icons.chevron_right, color: kTextMid, size: 22),
        IconButton(
          onPressed: _busy ? null : () => _delete([f], 'Delete this copy?'),
          icon: const Icon(Icons.delete_outline),
          color: kTextMid,
          tooltip: 'Delete',
        ),
      ]),
    );
    if (!opens) return body;
    // Conflict Backups are hidden from Obsidian - open them in the compare list.
    return InkWell(
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => BackupCompareListScreen(repo: widget.repo))),
        child: body);
  }

  @override
  Widget build(BuildContext context) {
    final folders = _folders;
    final total = (folders ?? []).fold(0, (sum, f) => sum + f.bytes);
    return Scaffold(
      backgroundColor: kVoid,
      appBar: AppBar(
        backgroundColor: kVoid,
        iconTheme: IconThemeData(color: kStar),
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.history, color: kTextMid, size: 20),
          const SizedBox(width: 8),
          Text('Backups', style: TextStyle(color: kStar, fontSize: 17)),
        ]),
      ),
      body: _error != null
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: Text('Could not read the backups: $_error',
                  style: TextStyle(color: kTextMid)))
          : folders == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Text(
                          'Your backup is your desktop - it keeps every version of your $_things. '
                          'These are one-off copies from linking and conflict fixes, safe to delete.',
                          style: TextStyle(
                              color: kTextMid, fontSize: 14, height: 1.4)),
                    ),
                    if (folders.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Text('No backups.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: kTextMid)),
                      ),
                    for (final f in folders) _row(f),
                    if (folders.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _busy
                            ? null
                            : () => _delete(folders, 'Delete all backups?'),
                        style: FilledButton.styleFrom(
                            backgroundColor: kGreen,
                            foregroundColor: kVoid,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14))),
                        child: _busy
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5, color: kVoid))
                            : Text('Delete all - free ${formatBytes(total)}',
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ],
                ),
    );
  }
}
