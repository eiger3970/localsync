// widgets/slow_sync_hint.dart
//
// 2026-11-10: small hint, shown only when a sync step runs slow.
// Owner: "just needs a small hint for when it runs slow... disappears
// too quickly, which is infuriating". Triggers 5 s into a sync, stays
// until the sync ends plus 15 s more (or until tapped). State is
// static so it survives any rebuild/recreation of the widget.

import 'dart:async';
import 'package:flutter/material.dart';
import '../theme.dart';
import 'progress_dog.dart';

class SlowSyncHint extends StatefulWidget {
  final bool syncing;
  const SlowSyncHint({super.key, required this.syncing});

  static const after = Duration(seconds: 5);
  static const lingerAfterDone = Duration(seconds: 15);

  static DateTime? _syncStart;
  static DateTime? _shownAt;
  static DateTime? _doneAt;

  /// Pure state step, testable: returns whether the hint is visible.
  static bool step(bool syncing, DateTime now) {
    if (syncing) {
      _doneAt = null;
      _syncStart ??= now;
      if (_shownAt == null && now.difference(_syncStart!) >= after) {
        _shownAt = now;
      }
    } else {
      _syncStart = null;
      if (_shownAt != null) {
        _doneAt ??= now;
        if (now.difference(_doneAt!) >= lingerAfterDone) {
          _shownAt = null;
          _doneAt = null;
        }
      }
    }
    return _shownAt != null;
  }

  static void dismiss() {
    _shownAt = null;
    _doneAt = null;
  }

  static void resetForTest() {
    _syncStart = null;
    _shownAt = null;
    _doneAt = null;
  }

  @override
  State<SlowSyncHint> createState() => _SlowSyncHintState();
}

class _SlowSyncHintState extends State<SlowSyncHint>
    with SingleTickerProviderStateMixin {
  Timer? _tick;
  // Owner: the dog needs movement so the user knows the app isn't frozen.
  late final AnimationController _bounce = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 450))
    ..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final show = SlowSyncHint.step(widget.syncing, DateTime.now());
    if (!show) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => setState(SlowSyncHint.dismiss),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _bounce,
              builder: (_, child) => Transform.translate(
                offset: Offset(0, -5 * Curves.easeInOut.transform(_bounce.value)),
                child: Transform.rotate(
                    angle: 0.12 * (_bounce.value - 0.5), child: child),
              ),
              child: const DogFigure(height: 24),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text('Big note or slow connection - still working.',
                  style: TextStyle(color: kStar, fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }
}
