// screens/deleted_files_screen.dart
//
// 2026-09-25: LocalSync main screen -> ⋮ -> Deleted files. Files deleted
// on either device, newest first; tap Restore to put one back. A restored
// file is a normal new file - the next Push sends it to the desktop.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/repository.dart';
import '../services/deleted_files.dart';
import '../services/repository_provider.dart';
import '../theme.dart';

class DeletedFilesScreen extends StatefulWidget {
  final Repository repo;
  const DeletedFilesScreen({super.key, required this.repo});

  @override
  State<DeletedFilesScreen> createState() => _DeletedFilesScreenState();
}

class _DeletedFilesScreenState extends State<DeletedFilesScreen> {
  List<DeletedFile>? _files;
  String? _error;
  final Set<String> _restored = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final files = await context
          .read<RepositoryProvider>()
          .withRepoFolder(widget.repo, (path) => listDeletedFiles(path));
      if (!mounted) return;
      setState(() => _files = files ?? []);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _restore(DeletedFile f) async {
    try {
      final written = await context
          .read<RepositoryProvider>()
          .withRepoFolder(widget.repo, (path) => restoreDeletedFile(path, f));
      if (!mounted || written == null) return;
      setState(() => _restored.add(f.path));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Restored: $written - swipe PUSH to send it to the desktop')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not restore: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('yyyy-MM-dd HH:mm');
    return Scaffold(
      backgroundColor: kVoid,
      appBar: AppBar(
        backgroundColor: kVoid,
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.restore_from_trash_outlined, color: kTextMid, size: 20),
          const SizedBox(width: 8),
          Text('Deleted files', style: TextStyle(color: kStar, fontSize: 17)),
        ]),
      ),
      body: _error != null
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: Text('Could not read the history: $_error',
                  style: TextStyle(color: kTextMid)))
          : _files == null
              ? const Center(child: CircularProgressIndicator())
              : _files!.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('No deleted files in "${widget.repo.name}".',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: kTextMid, fontSize: 15)),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _files!.length + 1,
                      separatorBuilder: (_, __) =>
                          Divider(color: kBorder, height: 1),
                      itemBuilder: (_, i) {
                        // 2026-09-26: Ken - "Deleted files - restore, does
                        // this cause an absolute mess? Can this be
                        // explained somewhere?" Said once, above the list.
                        if (i == 0) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.verified_user_outlined,
                                    color: kGreen, size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                      'RESTORE puts a file back where it was. '
                                      'It never replaces anything: if a file '
                                      'with that name is there now, the copy '
                                      'is named "(restored)". Then swipe PUSH '
                                      'to send it to the desktop.',
                                      style: TextStyle(
                                          color: kTextMid,
                                          fontSize: 13,
                                          height: 1.4)),
                                ),
                              ],
                            ),
                          );
                        }
                        final f = _files![i - 1];
                        final done = _restored.contains(f.path);
                        return ListTile(
                          leading: Icon(Icons.insert_drive_file_outlined,
                              color: kTextMid),
                          title: Text(f.path.split('/').last,
                              style: TextStyle(color: kStar, fontSize: 15)),
                          subtitle: Text(
                              '${f.path.contains('/') ? '${f.path.substring(0, f.path.lastIndexOf('/'))} - ' : ''}'
                              'deleted ${fmt.format(f.deletedAt)} on ${f.deletedBy}',
                              style: TextStyle(color: kTextMid, fontSize: 12)),
                          trailing: done
                              ? Icon(Icons.check_circle, color: kGreen)
                              : TextButton(
                                  onPressed: () => _restore(f),
                                  child: Text('RESTORE',
                                      style: TextStyle(
                                          color: kGreen,
                                          fontWeight: FontWeight.w700)),
                                ),
                        );
                      },
                    ),
    );
  }
}
