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
  final Duration after;
  const SlowSyncHint({super.key, this.after = const Duration(seconds: 5)});

  @override
  State<SlowSyncHint> createState() => _SlowSyncHintState();
}

class _SlowSyncHintState extends State<SlowSyncHint> {
  Timer? _timer;
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.after, () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
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
          border: Border(top: BorderSide(color: kGreen, width: 2)),
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
