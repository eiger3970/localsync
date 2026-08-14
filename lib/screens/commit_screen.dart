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
            const Text(
              'COMMIT MESSAGE',
              style: TextStyle(color: kTextDim, fontSize: 10, letterSpacing: 1.5),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _msgCtrl,
              autofocus: true,
              style: const TextStyle(color: kStar, fontSize: 13),
              decoration: const InputDecoration(hintText: '202502281200 quick sync'),
            ),
            const SizedBox(height: 20),
            const Text(
              'TEMPLATES',
              style: TextStyle(color: kTextDim, fontSize: 10, letterSpacing: 1.5),
            ),
            const SizedBox(height: 8),
            // Template list - sorted by usage frequency
            Expanded(
              child: ListView.separated(
                itemCount: templates.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: kBorder),
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
  void _afterCommit() {
    final result = _lastResult;
    if (!mounted || result == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(syncResultMessage(result)),
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

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      onTap: onTap,
      title: Text(
        template.pattern,
        style: TextStyle(
          color: isTopUsed ? kStar : kTextMid,
          fontSize: 12,
        ),
      ),
      trailing: template.useCount > 0
        ? Text(
            '${template.useCount}×',
            style: const TextStyle(color: kTextDim, fontSize: 10),
          )
        : null,
    );
  }
}
