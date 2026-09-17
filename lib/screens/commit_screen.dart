// screens/commit_screen.dart
// Commit message composer with ML-sorted templates.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../models/repository.dart';
import '../models/commit_template.dart';
import '../services/repository_provider.dart';
import '../services/sync_service.dart';
import '../widgets/gif_swipe_trigger.dart';
import '../widgets/sync_confirm_dialog.dart';

class CommitScreen extends StatefulWidget {
  final Repository repo;
  const CommitScreen({super.key, required this.repo});

  @override
  State<CommitScreen> createState() => _CommitScreenState();
}

class _CommitScreenState extends State<CommitScreen> {
  final _msgCtrl = TextEditingController();
  // 2026-08-14: see GifSwipeTrigger.onSettled's comment - _commit()
  // (onConfirm) only does the real push and stashes what happened here;
  // the snackbar + conditional pop moved to _afterCommit() (onSettled),
  // which only fires once the full swipe animation has actually played
  // out, not just whenever the network call happens to finish.
  SyncResult? _lastResult;

  @override
  void initState() {
    super.initState();
    _prefillTimestamp();
  }

  void _prefillTimestamp() {
    final ts = DateFormat('yyyyMMddHHmm').format(DateTime.now());
    _msgCtrl.text = '$ts quick sync';
    // Select "quick sync" so user types right over it
    _msgCtrl.selection = TextSelection(
      baseOffset: ts.length + 1,
      extentOffset: _msgCtrl.text.length,
    );
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RepositoryProvider>();
    final templates = provider.templates;

    return Scaffold(
      appBar: AppBar(title: Text(widget.repo.name.toUpperCase())),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 2026-09-17: real feedback, live - edit_note "looks
                // like an arrow pointing bottom left." Swapped for a
                // plain send glyph - unambiguous "message", and its own
                // natural diagonal already points the way PUSH does
                // throughout this app (top-right), so it can't be
                // misread as pointing the wrong way either.
                Icon(Icons.send_outlined, color: kTextDim, size: 14),
                const SizedBox(width: 4),
                Text(
                  'COMMIT MESSAGE',
                  style: TextStyle(
                      color: kTextDim, fontSize: 10, letterSpacing: 1.5),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _msgCtrl,
              autofocus: true,
              style: TextStyle(color: kStar, fontSize: 13),
              decoration: const InputDecoration(hintText: '202502281200 quick sync'),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(Icons.list_alt_outlined, color: kTextDim, size: 14),
                const SizedBox(width: 4),
                Text(
                  'TEMPLATES',
                  style: TextStyle(
                      color: kTextDim, fontSize: 10, letterSpacing: 1.5),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Template list - sorted by usage frequency
            Expanded(
              child: ListView.separated(
                itemCount: templates.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: kBorder),
                itemBuilder: (_, i) {
                  final t = templates[i];
                  return _TemplateTile(
                    template: t,
                    isTopUsed: i < 3 && t.useCount > 0,
                    onTap: () => _applyTemplate(t),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            // 2026-08-14: "the button needs to not be a tap, but the
            // consistency requires a swipe up for pushes... make the
            // button something that's consistent with the main page's
            // PUSH and gif swipe up, rather than the button" - first
            // pass just reused the gif asset behind a tap button, which
            // wasn't what was asked. This reuses the actual
            // GifSwipeTrigger the home screen's PUSH half uses
            // (extracted to widgets/gif_swipe_trigger.dart so both
            // screens share one real implementation), not a lookalike.
            // 2026-08-14: "the templates only show 1, but the full list
            // showing is better" - 220 ate too much of the list's space
            // for what this screen actually needs (a compact confirm
            // gesture, not a dedicated full-screen zone like the home
            // screen's PUSH half). Shrunk to give the list its room back.
            SizedBox(
              height: 130,
              child: GifSwipeTrigger(
                assetPath: 'assets/gifs/git_push.gif',
                caption: 'COMMIT & PUSH',
                swipeDown: false,
                gifHeight: 70,
                onConfirm: _commit,
                onSettled: _afterCommit,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _applyTemplate(CommitTemplate t) {
    final ts  = DateFormat('yyyyMMddHHmm').format(DateTime.now());
    final msg = '$ts ${t.pattern}';
    _msgCtrl.text = msg;

    // If template has a placeholder like [file], select it
    final bracketStart = msg.indexOf('[');
    final bracketEnd   = msg.indexOf(']');
    if (bracketStart != -1 && bracketEnd != -1) {
      _msgCtrl.selection = TextSelection(
        baseOffset:  bracketStart,
        extentOffset: bracketEnd + 1,
      );
    } else {
      _msgCtrl.selection = TextSelection.collapsed(offset: msg.length);
    }

    // Increment usage count
    context.read<RepositoryProvider>().useTemplate(t);
  }

  // 2026-08-14: this is now GifSwipeTrigger's onConfirm - the widget
  // itself races this against its own 2000ms-minimum/no-fake-completion
  // gif animation (see widgets/gif_swipe_trigger.dart), same contract
  // the home screen's PUSH swipe already uses. Nothing here needs to
  // manage that timing itself anymore.
  Future<void> _commit() async {
    final msg = _msgCtrl.text.trim();
    if (msg.isEmpty) return;
    if (widget.repo.id == null) return;

    // 2026-08-15: this was a complete stub - a 2s fake delay with a
    // "TODO: implement git add / commit / push via SSH" comment, doing
    // no real work at all. Now calls the real push() (see
    // sync_service.dart), same as every other sync action in the app,
    // just with the typed message instead of an auto-generated one.
    _lastResult = await context
        .read<RepositoryProvider>()
        .pushRepository(widget.repo.id!, commitMessage: msg);
  }

  // 2026-08-14 real-device finding: this used to pop unconditionally
  // with the result discarded - so "nothing to commit" (typed a
  // message but never actually edited a file) and a genuine failure
  // both looked identical to a successful commit+push: the screen
  // just closed with no explanation. Now shows what actually happened,
  // and only leaves the screen once something real went up.
  //
  // Runs as GifSwipeTrigger's onSettled - after the full swipe
  // animation (real push and its 2000ms floor, whichever is later) has
  // actually finished, not just whenever the network call resolves, so
  // landing back on the home screen doesn't cut the animation off
  // mid-flight with nothing continuing it there.
  // 2026-08-18: a SyncNeedsConfirmation result (see sync_service.dart)
  // means the swipe animation already played out, but the actual push
  // hasn't happened yet - show the plain-language summary now, and only
  // push for real (and only then possibly pop) if the user agrees.
  Future<void> _afterCommit() async {
    final result = _lastResult;
    if (!mounted || result == null) return;
    if (result case SyncNeedsConfirmation()) {
      final proceed = await showSyncConfirmDialog(context, result);
      if (proceed != true || !mounted) return;
      final msg = _msgCtrl.text.trim();
      _lastResult = await context.read<RepositoryProvider>().pushRepository(
          widget.repo.id!, commitMessage: msg, confirmed: true);
      if (!mounted) return;
      _afterCommit();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: kSurface,
        content: Text(syncResultMessage(result),
            style: TextStyle(color: kStar, fontSize: 16)),
        duration: const Duration(seconds: 12),
      ),
    );
    if (result is SyncOk) Navigator.pop(context);
  }
}

// ── Template tile ─────────────────────────────────────────────────────────────

class _TemplateTile extends StatelessWidget {
  final CommitTemplate template;
  final bool           isTopUsed;
  final VoidCallback   onTap;

  const _TemplateTile({
    required this.template,
    required this.isTopUsed,
    required this.onTap,
  });

  // 2026-09-17: real ask, live - add images per template ("add
  // (feature), fix (issue), merge (branch)"). Derived from the
  // pattern's own leading verb rather than hardcoded per string, so
  // this also covers the other shipped defaults (update/refactor/
  // remove/quick sync) and degrades to a plain generic icon for any
  // custom template a user creates that doesn't match a known verb -
  // same reasoning as every other icon fix this session, Material
  // icons only, no new SVG risk.
  static IconData _iconFor(String pattern) {
    final verb = pattern.split(' ').first.toLowerCase();
    return switch (verb) {
      'add' => Icons.add_circle_outline,
      // 2026-09-17: real feedback, live - "fix (issue) image is a bug,
      // change to repair tools like a spanner." handyman_outlined
      // (wrench + screwdriver crossed), not build_outlined (a single
      // wrench) - that one's already 'refactor' just below, and the
      // two need to stay visually distinct from each other, not just
      // both read as "a repair tool."
      'fix' => Icons.handyman_outlined,
      'merge' => Icons.call_merge,
      'update' => Icons.edit_outlined,
      'refactor' => Icons.build_outlined,
      'remove' => Icons.remove_circle_outline,
      'quick' => Icons.bolt_outlined,
      _ => Icons.description_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final color = isTopUsed ? kStar : kTextMid;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      onTap: onTap,
      leading: Icon(_iconFor(template.pattern), color: color, size: 18),
      minLeadingWidth: 0,
      title: Text(
        template.pattern,
        style: TextStyle(
          color: color,
          fontSize: 12,
        ),
      ),
      trailing: template.useCount > 0
        ? Text(
            '${template.useCount}×',
            style: TextStyle(color: kTextDim, fontSize: 10),
          )
        : null,
    );
  }
}
