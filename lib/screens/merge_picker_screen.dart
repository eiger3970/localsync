// screens/merge_picker_screen.dart
//
// 2026-08-26: the premium tier from docs/pricing-tiers.md - "IAP
// premium: automatic - put/yank individual pieces from each side."
// Everything else in this app's conflict resolution picks one whole
// side; this composes a merged result out of both, sentence by
// sentence, using line_diff.dart's mergeHunks/composeMerge. Real
// vimdiff is the explicit reference - "vimdiff which is amazing, but
// with phone easy tapping and simple." Left/right split-window layout,
// not stacked (this app's own existing vimdiff-style whole-side picker
// in conflict_picker_screen.dart went stacked specifically because a
// whole paragraph doesn't fit two columns readably on a phone - a
// single sentence does, which is exactly why line_diff.dart refines
// down to sentence-level hunks instead of stopping at paragraphs).
//
// Reuses the existing resolveConflict/backup/watchlist pipeline
// unchanged (see _confirm below, mirrors ConflictPickerScreen's
// _choose almost line for line) - the only new thing this screen adds
// is producing the [chosen] string via composeMerge instead of picking
// entry.versions[i].body wholesale. Every version not equal to that
// composed string still gets folded in as a reference callout by
// applyResolution, same safety net as every other resolution path.

import 'package:flutter/material.dart';
import '../theme.dart';
import '../models/repository.dart';
import '../services/conflict_scanner.dart';
import '../services/database_service.dart';
import '../services/line_diff.dart';
import '../services/resolved_watchlist.dart';
import '../services/vault_folder_service.dart';

class MergePickerScreen extends StatefulWidget {
  final Repository repo;
  final ConflictEntry entry;
  final String myDeviceName;
  const MergePickerScreen({
    super.key,
    required this.repo,
    required this.entry,
    required this.myDeviceName,
  });

  @override
  State<MergePickerScreen> createState() => _MergePickerScreenState();
}

class _MergePickerScreenState extends State<MergePickerScreen> {
  late final List<MergeHunk> _hunks;
  final Set<int> _theirsChosen = {};
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    final versions = widget.entry.versions;
    _hunks = mergeHunks(versions[0].body, versions[1].body);
  }

  String get _theirsLabel {
    final v = widget.entry.versions[1];
    return v.when != null ? '${v.who} - ${v.when}' : v.who;
  }

  String get _oursLabel =>
      widget.myDeviceName.isEmpty ? 'This device' : widget.myDeviceName;

  // 2026-08-26: mirrors ConflictPickerScreen._choose near-verbatim -
  // same backup-first resolveConflict call, same resolved-watchlist
  // record, same pop shape, only the composed [chosen] text differs.
  Future<void> _confirm() async {
    setState(() => _resolving = true);
    final chosen = composeMerge(_hunks, _theirsChosen);
    final vaultFolder = VaultFolderService();
    final path = await vaultFolder.startAccessing(widget.repo.vaultBookmark);
    String? backupRelPath;
    try {
      if (path != null) {
        backupRelPath = await resolveConflict(path, widget.entry, chosen);
        await DatabaseService().addResolvedRecords(
          recordsFor(widget.entry, DateTime.now()),
        );
      }
    } finally {
      await vaultFolder.stopAccessing(widget.repo.vaultBookmark);
    }
    if (mounted) {
      Navigator.pop(
        context,
        (
          resolved: true,
          vaultName: path?.split('/').last,
          backupRelPath: backupRelPath,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kVoid,
        title: Text('Merge pieces',
            style: TextStyle(color: kStar, fontSize: 16)),
      ),
      body: _resolving
          ? Center(child: CircularProgressIndicator(color: kGreen))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(widget.entry.filePath,
                      style: TextStyle(color: kTextMid, fontSize: 12.5)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(_oursLabel.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: kTextMid,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_theirsLabel.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: kTextMid,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: _hunks.length,
                    itemBuilder: (context, i) {
                      final h = _hunks[i];
                      if (h.op == HunkOp.same) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(h.ours,
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(color: kTextDim, fontSize: 12.5)),
                        );
                      }
                      final theirsPicked = _theirsChosen.contains(i);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: _MergePiece(
                                  text: h.ours,
                                  selected: !theirsPicked,
                                  onTap: () =>
                                      setState(() => _theirsChosen.remove(i)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _MergePiece(
                                  text: h.theirs,
                                  selected: theirsPicked,
                                  onTap: () =>
                                      setState(() => _theirsChosen.add(i)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: kTextDim.withValues(alpha: 0.3))),
                  ),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _confirm,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kGreen,
                            foregroundColor: kVoid,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          child: const Text('USE THIS MERGE',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w700)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Both full versions stay backed up either way - '
                        "nothing is lost by merging.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: kTextDim, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// One tappable piece in a conflict hunk - selected reads green (this
/// is what will be used), unselected amber (still safe, still backed
/// up, just not the active pick) - same convention as
/// ReferenceCalloutTile's kept/dropped sides in conflicts_screen.dart,
/// deliberately not red (red means something is being destroyed here,
/// nothing is).
class _MergePiece extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback onTap;
  const _MergePiece({
    required this.text,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: selected
              ? kGreen.withValues(alpha: 0.09)
              : Colors.amber.withValues(alpha: 0.09),
          border: Border.all(
              color: (selected ? kGreen : Colors.amber)
                  .withValues(alpha: selected ? 0.55 : 0.4)),
          borderRadius: BorderRadius.circular(8),
        ),
        // 2026-08-26: real feedback, live - "vimdiff has similar text
        // left and right and if it doesn't fit, it's higher or lower...
        // usually in a place where it's needed." A piece added on only
        // one side (the other never had it) has an empty string here -
        // real vimdiff shows a blank filler line to keep everything
        // else aligned; this screen doesn't need filler lines (same
        // content isn't duplicated per column at all, see the
        // same-hunk branch above), but an empty box with no text reads
        // as broken, not as "nothing was here." Says so directly
        // instead.
        child: Text(text.isEmpty ? '(nothing here)' : text,
            style: TextStyle(
                color: text.isEmpty ? kTextDim : kStar,
                fontSize: 12.5,
                fontStyle: text.isEmpty ? FontStyle.italic : FontStyle.normal,
                height: 1.4)),
      ),
    );
  }
}
