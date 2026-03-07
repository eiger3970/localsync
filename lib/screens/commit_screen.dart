// screens/commit_screen.dart
// Commit message composer with ML-sorted templates.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../models/repository.dart';
import '../models/commit_template.dart';
import '../services/repository_provider.dart';

class CommitScreen extends StatefulWidget {
  final Repository repo;
  const CommitScreen({super.key, required this.repo});

  @override
  State<CommitScreen> createState() => _CommitScreenState();
}

class _CommitScreenState extends State<CommitScreen> {
  final _msgCtrl = TextEditingController();
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
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _pushing ? null : _commit,
                child: _pushing
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(color: kVoid, strokeWidth: 2),
                    )
                  : const Text('COMMIT & PUSH'),
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

    setState(() => _pushing = true);
    // TODO: implement git add / commit / push via SSH
    await Future.delayed(const Duration(seconds: 2)); // placeholder
    setState(() => _pushing = false);

    if (mounted) Navigator.pop(context);
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
