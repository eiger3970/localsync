// screens/backup_compare_screen.dart
//
// 2026-09-06: real feedback, live - "why not a picker for this too?"
// The real word-diff picker (conflict_picker_screen.dart) only ever
// turns on for a conflict this app detected itself, via markers parsed
// out of one file. A recovery from content that already diverged
// outside git's view (this session's real incident) has no such
// marker - the "other version" is a separate file sitting in
// LocalSync/Conflict Backups. This lets a user manually pick one of
// those and compare it against its real live note in the same visual
// style, instead of reading both and retyping by hand.
//
// Deliberately whole-file tap-to-pick (the free/IAP "visual manual"
// tier from docs/pricing-tiers.md), not word-level put/yank - there's
// no marker-derived byte offset to splice at here, only two full file
// contents, so "replace the whole file with this side" is the correct
// action, not a false promise of finer-grained merging.

import 'dart:io';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../models/repository.dart';
import '../services/backup_compare.dart';
import '../services/vault_backup.dart';
import '../services/vault_folder_service.dart';
import '../services/word_diff.dart';

// 2026-09-06: same brighter red conflict_picker_screen.dart's own
// _kBrightRed uses for its "other side" panel - Material's default
// redAccent reads noticeably lower-contrast against this app's dark
// background than kGreen's neon punch at the same text size. Not
// imported from that file (private there) - small enough to duplicate
// rather than promote to a shared constant for one shared value.
const _kBrightRed = Color(0xFFFF3B30);

class BackupCompareListScreen extends StatefulWidget {
  final Repository repo;
  // 2026-09-07: real feedback, live - "the button... is better placed
  // in the actual opened conflict... for each backup." When set
  // (conflict_picker_screen.dart's own use), this screen lists only the
  // backups that belong to this one note - filename prefix-matched
  // against its base name, the same shape _backupConflictBeforeResolving
  // (conflict_scanner.dart) always writes: "$baseName - $timestamp.md".
  // Also skips the ambiguity-matching _open used for the old unscoped
  // list below (originalFileNameFromBackup/matchingLivePaths) - a
  // conflict already knows exactly which live note it's for, no need to
  // guess from the backup filename alone.
  final String? noteFilePath;
  const BackupCompareListScreen({
    super.key,
    required this.repo,
    this.noteFilePath,
  });

  @override
  State<BackupCompareListScreen> createState() =>
      _BackupCompareListScreenState();
}

class _BackupCompareListScreenState extends State<BackupCompareListScreen> {
  final _vaultFolder = VaultFolderService();
  late Future<List<String>> _future;

  // 2026-09-07: see BackupCompareListScreen.noteFilePath's own doc - the
  // exact prefix _backupConflictBeforeResolving writes for this note.
  String? get _scopedPrefix {
    final notePath = widget.noteFilePath;
    if (notePath == null) return null;
    final baseName = notePath.split('/').last.replaceAll('.md', '');
    return '$baseName - ';
  }

  @override
  void initState() {
    super.initState();
    _future = _list();
  }

  Future<List<String>> _list() async {
    final path = await _vaultFolder.startAccessing(widget.repo.vaultBookmark);
    if (path == null) return const [];
    try {
      final dir = Directory('$path/$kLocalSyncFolderName/Conflict Backups');
      if (!await dir.exists()) return const [];
      var names = await dir
          .list()
          .where((e) => e is File)
          .map((e) => e.uri.pathSegments.last)
          .toList();
      final prefix = _scopedPrefix;
      if (prefix != null) {
        names = names.where((n) => n.startsWith(prefix)).toList();
      }
      // Filenames are YYYYMMDDhhmm-suffixed - a plain reverse string
      // sort already puts the newest first, same as the timestamp
      // itself would.
      names.sort((a, b) => b.compareTo(a));
      return names;
    } finally {
      await _vaultFolder.stopAccessing(widget.repo.vaultBookmark);
    }
  }

  Future<void> _open(String backupName) async {
    // Scoped case: the live path is already known (the conflict this
    // list was opened from) - no need to guess it back out of the
    // backup filename, which conflict-resolution backups don't even
    // carry a recognized label for (see originalFileNameFromBackup's
    // own doc - a different filename shape than this scoped case).
    final notePath = widget.noteFilePath;
    if (notePath != null) {
      final path =
          await _vaultFolder.startAccessing(widget.repo.vaultBookmark);
      if (path == null) return;
      String backupContent;
      try {
        backupContent = await File(
                '$path/$kLocalSyncFolderName/Conflict Backups/$backupName')
            .readAsString();
      } finally {
        await _vaultFolder.stopAccessing(widget.repo.vaultBookmark);
      }
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BackupComparePickerScreen(
            repo: widget.repo,
            livePath: notePath,
            backupName: backupName,
            backupContent: backupContent,
          ),
        ),
      );
      return;
    }
    final original = originalFileNameFromBackup(backupName);
    if (original == null) {
      _showMessage('Can\'t tell which note this backup is for.');
      return;
    }
    final path = await _vaultFolder.startAccessing(widget.repo.vaultBookmark);
    if (path == null) return;
    List<String> matches;
    String backupContent;
    try {
      final allFiles = await Directory(path)
          .list(recursive: true)
          .where((e) => e is File && e.path.endsWith('.md'))
          .map((e) => e.path.substring(path.length + 1))
          .toList();
      matches = matchingLivePaths(allFiles, original);
      backupContent = await File(
              '$path/$kLocalSyncFolderName/Conflict Backups/$backupName')
          .readAsString();
    } finally {
      await _vaultFolder.stopAccessing(widget.repo.vaultBookmark);
    }
    if (!mounted) return;
    if (matches.isEmpty) {
      _showMessage('No live note named "$original" found in the vault.');
      return;
    }
    if (matches.length > 1) {
      _showMessage(
          '"$original" exists in more than one folder - open it in Obsidian '
          'and compare by hand instead, to be sure which one this backup is '
          'really for.');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BackupComparePickerScreen(
          repo: widget.repo,
          livePath: matches.single,
          backupName: backupName,
          backupContent: backupContent,
        ),
      ),
    );
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: kSurface,
        content: Text(text, style: TextStyle(color: kStar, fontSize: 14)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kVoid,
        title: Text('Compare with a backup', style: TextStyle(color: kStar)),
      ),
      body: FutureBuilder<List<String>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final names = snapshot.data ?? const [];
          if (names.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                    widget.noteFilePath != null
                        ? 'No backups yet for this note.'
                        : 'No backups in LocalSync/Conflict Backups yet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: kTextMid, fontSize: 15)),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: names.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final name = names[i];
              return Material(
                color: kSurface,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _open(name),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(Icons.description_outlined,
                            color: kTextMid, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(name,
                              style:
                                  TextStyle(color: kStar, fontSize: 14)),
                        ),
                        Icon(Icons.chevron_right, color: kTextDim, size: 20),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class BackupComparePickerScreen extends StatefulWidget {
  final Repository repo;
  final String livePath;
  final String backupName;
  final String backupContent;
  const BackupComparePickerScreen({
    super.key,
    required this.repo,
    required this.livePath,
    required this.backupName,
    required this.backupContent,
  });

  @override
  State<BackupComparePickerScreen> createState() =>
      _BackupComparePickerScreenState();
}

class _BackupComparePickerScreenState
    extends State<BackupComparePickerScreen> {
  final _vaultFolder = VaultFolderService();
  String? _liveContent;
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    _loadLive();
  }

  Future<void> _loadLive() async {
    final path = await _vaultFolder.startAccessing(widget.repo.vaultBookmark);
    if (path == null) return;
    String content;
    try {
      content = await File('$path/${widget.livePath}').readAsString();
    } finally {
      await _vaultFolder.stopAccessing(widget.repo.vaultBookmark);
    }
    if (mounted) setState(() => _liveContent = content);
  }

  Future<void> _choose(String content) async {
    if (_resolving) return;
    setState(() => _resolving = true);
    final path = await _vaultFolder.startAccessing(widget.repo.vaultBookmark);
    try {
      if (path != null) {
        await File('$path/${widget.livePath}').writeAsString(content);
      }
    } finally {
      await _vaultFolder.stopAccessing(widget.repo.vaultBookmark);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final live = _liveContent;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kVoid,
        title: Text(widget.livePath.split('/').last,
            style: TextStyle(color: kStar), overflow: TextOverflow.ellipsis),
      ),
      body: live == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tap the version to keep - it replaces the live note.',
                      style: TextStyle(color: kTextMid, fontSize: 13)),
                  const SizedBox(height: 12),
                  Expanded(
                    child: live.length <= maxDiffTokens * 6 &&
                            widget.backupContent.length <= maxDiffTokens * 6
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: _Panel(
                                  title: 'Live note',
                                  text: live,
                                  tokens: wordDiffOurs(
                                      live, widget.backupContent),
                                  color: kGreen,
                                  onTap: _resolving
                                      ? null
                                      : () => _choose(live),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _Panel(
                                  title: 'Backup (${widget.backupName})',
                                  text: widget.backupContent,
                                  tokens: wordDiffTheirs(
                                      live, widget.backupContent),
                                  color: _kBrightRed,
                                  onTap: _resolving
                                      ? null
                                      : () => _choose(widget.backupContent),
                                ),
                              ),
                            ],
                          )
                        // 2026-09-06: same "too big/complex to diff usefully,
                        // fall back to plain text" bias word_diff.dart's own
                        // maxDiffTokens doc already states, and
                        // conflict_picker_screen.dart's useDiff check already
                        // applies for real detected conflicts - matched here
                        // rather than silently truncating or crashing on a
                        // large note.
                        : Column(
                            children: [
                              Expanded(
                                child: _Panel(
                                  title: 'Live note',
                                  text: live,
                                  tokens: null,
                                  color: kGreen,
                                  onTap: _resolving
                                      ? null
                                      : () => _choose(live),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Expanded(
                                child: _Panel(
                                  title: 'Backup (${widget.backupName})',
                                  text: widget.backupContent,
                                  tokens: null,
                                  color: _kBrightRed,
                                  onTap: _resolving
                                      ? null
                                      : () => _choose(widget.backupContent),
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final String text;
  final List<DiffToken>? tokens;
  final Color color;
  final VoidCallback? onTap;
  const _Panel({
    required this.title,
    required this.text,
    required this.tokens,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kSurface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: color, fontSize: 13, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Expanded(
                child: SingleChildScrollView(
                  child: tokens == null
                      ? Text(text,
                          style: TextStyle(color: kStar, fontSize: 13))
                      : Text.rich(
                          TextSpan(
                            children: tokens!
                                .map((t) => TextSpan(
                                      text: t.text,
                                      style: t.op == DiffOp.equal
                                          ? TextStyle(
                                              color: kStar, fontSize: 13)
                                          : TextStyle(
                                              color: kStar,
                                              fontSize: 13,
                                              backgroundColor: color
                                                  .withValues(alpha: 0.28),
                                            ),
                                    ))
                                .toList(),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
