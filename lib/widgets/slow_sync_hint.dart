// widgets/slow_sync_hint.dart
//
// 2026-11-10: owner-approved courtesy message - "Big note or slow
// connection is courteous, include svg like doggy image beside it."
// Shown only when a sync step has run longer than [after] (default 5 s);
// quick syncs never see it. Reassures: still working, nothing lost.

import 'dart:async';
import 'package:flutter/material.dart';
import '../theme.dart';
import 'progress_dog.dart';

class SlowSyncHint extends StatefulWidget {
  final bool syncing;
  final Duration after;
  final Duration minVisible;
  const SlowSyncHint({
    super.key,
    required this.syncing,
    this.after = const Duration(seconds: 5),
    this.minVisible = const Duration(seconds: 12),
  });

  @override
  State<SlowSyncHint> createState() => _SlowSyncHintState();
}

// 2026-11-10: owner - hint flashed "in a split second" when the sync
// ended right after it appeared. Once shown it now stays at least
// [minVisible] so it can be read.
class _SlowSyncHintState extends State<SlowSyncHint> {
  Timer? _showTimer;
  Timer? _hideTimer;
  DateTime? _shownAt;
  bool _show = false;

  @override
  void initState() {
    super.initState();
    if (widget.syncing) _start();
  }

  @override
  void didUpdateWidget(SlowSyncHint old) {
    super.didUpdateWidget(old);
    if (widget.syncing && !old.syncing) _start();
    if (!widget.syncing && old.syncing) _stop();
  }

  void _start() {
    _hideTimer?.cancel();
    _showTimer?.cancel();
    if (_show) return;
    _showTimer = Timer(widget.after, () {
      if (!mounted) return;
      setState(() {
        _show = true;
        _shownAt = DateTime.now();
      });
    });
  }

  void _stop() {
    _showTimer?.cancel();
    if (!_show) return;
    final left =
        widget.minVisible - DateTime.now().difference(_shownAt!);
    _hideTimer = Timer(left.isNegative ? Duration.zero : left, () {
      if (mounted) setState(() => _show = false);
    });
  }

  @override
  void dispose() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: kSurface,
          border: Border(bottom: BorderSide(color: kGreen, width: 2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const DogFigure(height: 40),
            const SizedBox(width: 14),
            Flexible(
              child: Text(
                'Big note or slow connection.\nStill working - nothing is lost.',
                style: TextStyle(
                    color: kStar,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
