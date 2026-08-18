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
          // 2026-08-18: "too small and dark", "too verbose, create svg
          // images" - a full paragraph in dim small text asked the user
          // to read to feel reassured, the opposite of reassuring.
          // Built-in icons (not custom SVG - real rendering risk with
          // no way to preview them, per pairing_laptop_lock.svg's own
          // "took many iterations" history) walk the 3-step safety
          // story at a glance: conflict -> both saved -> pick anytime.
          // Full detail (exact folder name) stays one tap away via the
          // info button, not deleted - "Show details" is the same
          // pattern the sync-confirm dialog already uses.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: kSurface,
            child: Row(
              children: [
                const Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _SafetyStep(
                        icon: Icons.compare_arrows,
                        label: 'Conflict',
                      ),
                      Icon(Icons.arrow_forward, color: kTextDim, size: 18),
                      _SafetyStep(
                        icon: Icons.backup,
                        label: 'Both saved',
                      ),
                      Icon(Icons.arrow_forward, color: kTextDim, size: 18),
                      _SafetyStep(
                        icon: Icons.touch_app,
                        label: 'Pick anytime',
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.info_outline, color: kTextMid),
                  tooltip: 'How this works',
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      backgroundColor: kSurface,
                      title: const Text('How conflicts are kept safe',
                          style: TextStyle(color: kStar, fontSize: 17)),
                      content: const Text(
                        'Resolving a conflict always saves both full '
                        'versions to "LocalSync Conflict Backups" in '
                        'your vault first, before anything is changed. '
                        'Nothing is lost, even if you pick the wrong '
                        'one - just open that note in Obsidian to find '
                        'the other version.',
                        style: TextStyle(color: kTextMid, fontSize: 14),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Got it',
                              style: TextStyle(color: kStar, fontSize: 15)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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

class _SafetyStep extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SafetyStep({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: kGreen, size: 26),
        const SizedBox(height: 4),
        // 2026-08-18: bumped from the old paragraph's dim 13px/kTextMid
        // to kStar/14px - "too small and dark, make easier to read".
        Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: kStar, fontSize: 12)),
      ],
    );
  }
}
