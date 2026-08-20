// screens/conflicts_screen.dart
//
// 2026-08-18: step 1 of the conflict-picker plan - see
// conflict_scanner.dart's header for why this is a live scan with no
// persisted state. This screen only lists what needs review and says
// where/who/when; tapping through to actually fix a file still happens
// in Obsidian by hand for now - the tap-to-pick resolution UI is the
// deliberately deferred step 2, once this list itself proves useful.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../models/repository.dart';
import '../services/conflict_scanner.dart';
import '../services/database_service.dart';
import '../services/ios_app_service.dart';
import '../services/resolved_watchlist.dart';
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
  // 2026-08-20: filePaths of entries this scan found that match a
  // previously-resolved signature - see resolved_watchlist.dart. Keyed by
  // filePath rather than by entry identity since ConflictEntry has no id
  // of its own and filePath is unique enough for this app's one-conflict-
  // per-note-in-practice usage.
  Set<String> _revertedPaths = {};

  @override
  void initState() {
    super.initState();
    _future = _scan();
  }

  Future<List<ConflictEntry>> _scan() async {
    final path = await _vaultFolder.startAccessing(widget.repo.vaultBookmark);
    if (path == null) return const [];
    try {
      final entries = await scanForConflicts(path);
      // 2026-08-20: real device feedback, live - scanForConflicts returns
      // filesystem order, not recency, so a brand-new conflict can land
      // behind older accumulated ones in the list. That's exactly what
      // makes the auto-navigation into this screen feel like an ambush -
      // "shows a bunch of new data the user doesn't know about." Most
      // recent first means whatever the user just triggered is always
      // the first thing they see, not something they have to hunt for
      // past older, already-known entries. `when` is YYYYMMDDhhmm, so a
      // plain string compare already sorts chronologically; entries with
      // no timestamp (shouldn't normally happen - every stacked entry
      // has at least one non-"yours" version) sort last, not first.
      entries.sort((a, b) => (b.when ?? '').compareTo(a.when ?? ''));
      await _checkForReverts(entries);
      return entries;
    } finally {
      await _vaultFolder.stopAccessing(widget.repo.vaultBookmark);
    }
  }

  Future<void> _checkForReverts(List<ConflictEntry> entries) async {
    final db = DatabaseService();
    final now = DateTime.now();
    final watchlist = pruneOld(await db.getResolvedWatchlist(), now);
    final reverted = findReverted(entries, watchlist);
    if (mounted) {
      setState(() => _revertedPaths = reverted.map((r) => r.filePath).toSet());
    }
    // Persist unconditionally: flushes both expired entries (already
    // dropped by pruneOld above) and matched ones (already done their
    // job - flagged once, no need to keep re-flagging every future scan
    // of the same file).
    final remaining = watchlist.where((r) => !reverted.any((m) =>
        m.filePath == r.filePath && m.who == r.who && m.when == r.when));
    await db.setResolvedWatchlist(remaining.toList());
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
                      // 2026-08-18: "still too small and dark", "need a
                      // clearer location" - bumped to kStar/16px to
                      // match the rest of the app's readable text, and
                      // named the exact spot instead of the vague "in
                      // your vault": a normal top-level folder, visible
                      // in Obsidian's own file list like any other
                      // folder, not hidden or app-only.
                      content: const Text(
                        'Resolving a conflict always saves both full '
                        'versions first, before anything is changed.\n\n'
                        'Location: open Obsidian, look at your file '
                        'list (the folder icon in the left sidebar) - '
                        'there\'s a folder called "LocalSync Conflict '
                        'Backups" at the top level, right alongside '
                        'your other folders. Nothing is lost, even if '
                        'you pick the wrong one - just open the note '
                        'inside it to find the other version.',
                        style: TextStyle(color: kStar, fontSize: 16),
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
                    // 2026-08-20: this exact conflict was resolved before
                    // and has now reappeared - most likely Obsidian's own
                    // cache reverting the write (see resolved_watchlist.dart)
                    // rather than a brand new conflict. Called out
                    // explicitly instead of looking like an unremarkable
                    // first-time entry, since the user already thought
                    // this one was handled.
                    final reappeared = _revertedPaths.contains(e.filePath);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: reappeared
                          ? const Icon(Icons.warning_amber,
                              color: Colors.amber, size: 22)
                          : null,
                      title: Text(e.filePath,
                          style: const TextStyle(color: kStar, fontSize: 15)),
                      subtitle: Text(
                        reappeared
                            ? 'Resolved earlier, but this looks like it '
                                'came back - possibly reverted by Obsidian. '
                                'Check the backup note if unsure.'
                            : (e.versions.length > 2
                                ? '${e.versions.length - 1} unresolved versions '
                                    'stacked - most recent by ${e.who}'
                                : (e.when != null
                                    ? 'Conflicting change by ${e.who} - ${e.when}'
                                    : 'Conflicting change by ${e.who}')),
                        style: TextStyle(
                            color: reappeared ? Colors.amber : kTextMid,
                            fontSize: 13),
                      ),
                      trailing:
                          const Icon(Icons.chevron_right, color: kTextDim),
                      onTap: () async {
                        final result =
                            await Navigator.push<ConflictResolvedResult>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ConflictPickerScreen(
                                repo: widget.repo, entry: e),
                          ),
                        );
                        if (result?.resolved == true) {
                          setState(() => _future = _scan());
                          // 2026-08-19: tried deep-linking straight to
                          // the exact backup note (obsidian://open?
                          // vault=...&file=...) - real device testing
                          // found Obsidian doesn't honor the folder
                          // portion of that path the way expected: it
                          // silently opened a same-named file from a
                          // completely unrelated old vault-backup
                          // snapshot instead, twice, with two different
                          // URL-encoding approaches. Showing WRONG
                          // content is worse than making the user
                          // navigate themselves, so this fell back to
                          // opening just the vault (already
                          // proven-reliable elsewhere - see
                          // linking_controller.dart's openObsidianNow())
                          // paired with an explicit folder name in the
                          // message, rather than a broken file-specific
                          // link.
                          final vaultName = result?.vaultName;
                          if (vaultName != null && context.mounted) {
                            // 2026-08-19: real bug, live - "Both
                            // versions" is wrong once a note has 3+
                            // stacked versions (see the Kanban
                            // multi-version test this session), not
                            // just the common 2-way case.
                            final versionWord = e.versions.length == 2
                                ? 'Both versions'
                                : 'All ${e.versions.length} versions';
                            // 2026-08-19: "why is the button link needed?
                            // ... make 'backed up' a link" - first pass
                            // linked the verb. Real follow-up: "ideally
                            // the link would be better in the actual
                            // location the text says at the end of the
                            // sentence" - a link should name the
                            // destination, not the action, so it moved
                            // onto "LocalSync Conflict Backups" instead.
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: kSurface,
                                content: Text.rich(
                                  TextSpan(
                                    style: const TextStyle(
                                        color: kStar, fontSize: 15),
                                    children: [
                                      TextSpan(
                                          text: 'Resolved. $versionWord '
                                              'backed up in '),
                                      TextSpan(
                                        text: 'LocalSync Conflict Backups',
                                        style: const TextStyle(
                                          color: kGreen,
                                          fontWeight: FontWeight.bold,
                                          decoration:
                                              TextDecoration.underline,
                                        ),
                                        recognizer: TapGestureRecognizer()
                                          ..onTap = () {
                                            IosAppServiceImpl().openObsidian(
                                                vaultName: vaultName);
                                          },
                                      ),
                                      const TextSpan(text: '.'),
                                    ],
                                  ),
                                ),
                                duration: const Duration(seconds: 8),
                              ),
                            );
                          }
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
