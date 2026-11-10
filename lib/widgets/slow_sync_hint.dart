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
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const DogFigure(height: 22),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Big note or slow connection - still working.\nNothing is lost.',
              style: TextStyle(color: kTextMid, fontSize: 11, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}
