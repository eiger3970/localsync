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
import '../widgets/action_gif.dart';

class CommitScreen extends StatefulWidget {
  final Repository repo;
  const CommitScreen({super.key, required this.repo});

  @override
  State<CommitScreen> createState() => _CommitScreenState();
}

class _CommitScreenState extends State<CommitScreen> {
  final _msgCtrl = TextEditingController();
  final _gifKey = GlobalKey<ActionGifState>();
  bool _pushing = false;

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
            // 2026-08-14: "Either the tap button commit and push is a
            // swipe up of the push up gif or the switching to main page
            // shows the pushup gif running" - real device feedback that
            // this screen's plain spinner didn't match the home screen's
            // push gif at all. A drag-swipe gesture doesn't fit this
            // screen (there's already a deliberate tap-to-confirm step
            // after typing a message), so this reuses the same
            // ActionGif + asset instead - same real-progress-not-faked
            // trigger() contract as the home screen's swipe, just
            // fired by a tap here.
            Center(
              child: ActionGif(
                key: _gifKey,
                assetPath: 'assets/gifs/git_push.gif',
                height: 80,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _pushing ? null : _commit,
                child: const Text('COMMIT & PUSH'),
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

  Future<void> _commit() async {
    final msg = _msgCtrl.text.trim();
    if (msg.isEmpty) return;
    if (widget.repo.id == null) return;

    setState(() => _pushing = true);
    // 2026-08-15: this was a complete stub - a 2s fake delay with a
    // "TODO: implement git add / commit / push via SSH" comment, doing
    // no real work at all. Now calls the real push() (see
    // sync_service.dart), same as every other sync action in the app,
    // just with the typed message instead of an auto-generated one.
    //
    // 2026-08-14: wrapped in the gif's trigger() (see the ActionGif
    // widget above) instead of a bare await - races the real push
    // against the same 2000ms-minimum/no-fake-completion contract the
    // home screen's swipe-push already uses, so this screen's gif
    // isn't just decorative, it reflects the actual operation.
    SyncResult? result;
    await _gifKey.currentState?.trigger(() async {
      result = await context
          .read<RepositoryProvider>()
          .pushRepository(widget.repo.id!, commitMessage: msg);
    });
    if (!mounted) return;
    setState(() => _pushing = false);

    // 2026-08-14 real-device finding: this used to pop unconditionally
    // with the result discarded - so "nothing to commit" (typed a
    // message but never actually edited a file) and a genuine failure
    // both looked identical to a successful commit+push: the screen
    // just closed with no explanation. Now mirrors home_screen.dart's
    // feedback - show what actually happened, and only leave the
    // screen once something real went up, so a no-op or error stays
    // visible and actionable instead of silently discarding the typed
    // message.
    final finalResult = result;
    if (finalResult == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(syncResultMessage(finalResult)),
        duration: const Duration(seconds: 12),
      ),
    );
    if (finalResult is SyncOk && mounted) Navigator.pop(context);
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
