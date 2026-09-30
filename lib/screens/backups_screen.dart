// screens/backups_screen.dart
//
// 2026-09-29: Ken - Backups: every LocalSync safety-copy folder with its
// file count and size, one Clean up button that keeps the newest Backup,
// then a sync straight away ("A sync needs to run after a fix") so the
// desktop is cleaned too. Approved from the HTML preview the same day.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/repository.dart';
import '../services/localsync_cleanup.dart';
import 'backup_compare_screen.dart';
import '../services/repository_provider.dart';
import '../theme.dart';

class BackupsScreen extends StatefulWidget {
  final Repository repo;
  const BackupsScreen({super.key, required this.repo});

  @override
  State<BackupsScreen> createState() => _BackupsScreenState();
}

class _BackupsScreenState extends State<BackupsScreen> {
  List<BackupFolder>? _folders;
  String? _error;
  bool _busy = false;
  String _step = '';
  int? _freed;

  @override
  void initState() {
    super.initState();
    _load();
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

  int get _cleanable => (_folders ?? [])
      .where((f) => !f.keep)
      .fold(0, (sum, f) => sum + f.bytes);

  Future<void> _cleanUp() async {
    final provider = context.read<RepositoryProvider>();
    final folders = _folders ?? [];
    setState(() {
      _busy = true;
      _step = 'Cleaning up';
    });
    try {
      final freed = await provider.withRepoFolder(
          widget.repo, (path) => cleanUpBackupFolders(path, folders));
      if (!mounted) return;
      setState(() => _step = 'Sending to your desktop');
      final id = widget.repo.id;
      if (id != null) {
        // confirmed: these removals are the point, not an accident.
        await provider.pushRepository(id,
            commitMessage: 'Clean up LocalSync backups', confirmed: true);
        await provider.triggerDesktopSyncNow(id);
      }
      await _load();
      if (mounted) setState(() => _freed = freed ?? 0);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // 2026-09-30: Conflict Backups are hidden from Obsidian now - tap the
  // row to open them in the compare list.
  Widget _row(BackupFolder f) => f.name == 'Conflict Backups'
      ? InkWell(
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => BackupCompareListScreen(repo: widget.repo))),
          child: _rowBody(f, open: true))
      : _rowBody(f);

  Widget _rowBody(BackupFolder f, {bool open = false}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration:
            BoxDecoration(border: Border(top: BorderSide(color: kBorder))),
        child: Row(children: [
          Icon(Icons.folder_outlined,
              color: f.keep ? kGreen : kTextMid, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: kStar,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600)),
                Text.rich(TextSpan(children: [
                  TextSpan(text: '${f.files} file${f.files == 1 ? '' : 's'}'),
                  if (f.keep)
                    TextSpan(
                        text: f.phoneOnly
                            ? ' · THIS PHONE ONLY, KEPT'
                            : ' · NEWEST, KEPT',
                        style: TextStyle(
                            color: kGreen, fontWeight: FontWeight.w700)),
                ]), style: TextStyle(color: kTextDim, fontSize: 12.5)),
              ],
            ),
          ),
          Text(formatBytes(f.bytes),
              style: TextStyle(
                  color: kStar, fontSize: 14, fontWeight: FontWeight.w700)),
          if (open) Icon(Icons.chevron_right, color: kTextMid, size: 22),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final folders = _folders;
    final shown = _freed == null
        ? (folders ?? [])
        : (folders ?? []).where((f) => f.keep).toList();
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
                    if (_freed != null) ...[
                      const SizedBox(height: 16),
                      Icon(Icons.check_circle_outline, color: kGreen, size: 64),
                      const SizedBox(height: 8),
                      Text('${formatBytes(_freed!)} freed',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: kGreen,
                              fontSize: 22,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(
                          'Full copies kept, on this phone only.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: kTextMid, fontSize: 14, height: 1.45)),
                      const SizedBox(height: 14),
                    ] else
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Text(
                            'Safety copies of ${widget.repo.name}, kept out '
                            'of Obsidian. Your own notes are never in here.',
                            style: TextStyle(
                                color: kTextMid, fontSize: 13.5, height: 1.4)),
                      ),
                    if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Text('No backups yet.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: kTextMid)),
                      ),
                    for (final f in shown) _row(f),
                    if (_freed == null && _cleanable > 0) ...[
                      Container(
                        padding: const EdgeInsets.fromLTRB(0, 12, 0, 16),
                        decoration: BoxDecoration(
                            border: Border(top: BorderSide(color: kBorder))),
                        child: Row(children: [
                          Expanded(
                              child: Text('Clean up frees',
                                  style: TextStyle(color: kTextMid))),
                          Text(formatBytes(_cleanable),
                              style: TextStyle(
                                  color: kStar, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                      FilledButton(
                        onPressed: _busy ? null : _cleanUp,
                        style: FilledButton.styleFrom(
                            backgroundColor: kGreen,
                            foregroundColor: kVoid,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14))),
                        child: _busy
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2.5, color: kVoid)),
                                  const SizedBox(width: 10),
                                  Text('$_step...',
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800)),
                                ])
                            : Text('Clean up - free ${formatBytes(_cleanable)}',
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(height: 10),
                      Text(
                          'Full copies are always kept. Conflict copies are '
                          'removed by themselves after 30 days anyway.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: kTextDim, fontSize: 12.5)),
                    ],
                  ],
                ),
    );
  }
}
