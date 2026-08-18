// screens/conflicts_screen.dart
//
// 2026-08-18: step 1 of the conflict-picker plan - see
// conflict_scanner.dart's header for why this is a live scan with no
// persisted state. This screen only lists what needs review and says
// where/who/when; tapping through to actually fix a file still happens
// in Obsidian by hand for now - the tap-to-pick resolution UI is the
// deliberately deferred step 2, once this list itself proves useful.

import 'package:flutter/material.dart';
import '../theme.dart';
import '../models/repository.dart';
import '../services/conflict_scanner.dart';
import '../services/vault_folder_service.dart';
import 'conflict_picker_screen.dart';

class ConflictsScreen extends StatefulWidget {
  final Repository repo;
  const ConflictsScreen({super.key, required this.repo});

  @override
  State<ConflictsScreen> createState() => _ConflictsScreenState();
}

class _ConflictsScreenState extends State<ConflictsScreen> {
  final _vaultFolder = VaultFolderService();
  late Future<List<ConflictEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = _scan();
  }

  Future<List<ConflictEntry>> _scan() async {
    final path = await _vaultFolder.startAccessing(widget.repo.vaultBookmark);
    if (path == null) return const [];
    try {
      return await scanForConflicts(path);
    } finally {
      await _vaultFolder.stopAccessing(widget.repo.vaultBookmark);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kVoid,
      appBar: AppBar(
        backgroundColor: kVoid,
        title: const Text('Conflicts', style: TextStyle(color: kStar)),
      ),
      body: Column(
        children: [
          // 2026-08-18: "valuable information a user needs to know,
          // ensure this is somewhere easy for users to be aware of" -
          // shown here, before any specific conflict is even opened, so
          // the reassurance lands on approach rather than only inside
          // the confirm dialog at the moment of deciding. Always
          // visible on this screen, not just when conflicts exist.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: kSurface,
            child: const Text(
              'Resolving a conflict always saves both full versions to '
              '"LocalSync Conflict Backups" in your vault first - '
              'nothing is lost, even if you pick the wrong one.',
              style: TextStyle(color: kTextMid, fontSize: 13),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<ConflictEntry>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(
                    child: CircularProgressIndicator(color: kGreen),
                  );
                }
                final entries = snapshot.data ?? const [];
                if (entries.isEmpty) {
                  return const Center(
                    child: Text('No unresolved conflicts.',
                        style: TextStyle(color: kTextMid, fontSize: 15)),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(color: kTextDim),
                  itemBuilder: (context, i) {
                    final e = entries[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(e.filePath,
                          style: const TextStyle(color: kStar, fontSize: 15)),
                      subtitle: Text(
                        e.when != null
                            ? 'Conflicting change by ${e.who} - ${e.when}'
                            : 'Conflicting change by ${e.who}',
                        style: const TextStyle(color: kTextMid, fontSize: 13),
                      ),
                      trailing:
                          const Icon(Icons.chevron_right, color: kTextDim),
                      onTap: () async {
                        final resolved = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ConflictPickerScreen(
                                repo: widget.repo, entry: e),
                          ),
                        );
                        if (resolved == true) {
                          setState(() => _future = _scan());
                        }
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
