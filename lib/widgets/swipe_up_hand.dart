import 'package:flutter/material.dart';
import '../theme.dart';

/// 2026-11-11 owner: the PUSH zone must not glow like a button (PUSH is a swipe up, not a tap). A hand that swipes
/// up, fading and glowing green, sits above the normal PUSH label until the push has been done.
class SwipeUpHand extends StatefulWidget {
  const SwipeUpHand({super.key});
  @override
  State<SwipeUpHand> createState() => _SwipeUpHandState();
}

class _SwipeUpHandState extends State<SwipeUpHand> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    return SizedBox(
      height: 64,
      child: Center(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, child) {
            final t = still ? 0.5 : Curves.easeInOut.transform(_c.value);
            final fade = still ? 1.0 : (t < 0.2 ? t / 0.2 : (t > 0.8 ? (1 - t) / 0.2 : 1.0));
            return Opacity(
              opacity: fade.clamp(0.0, 1.0),
              child: Transform.translate(offset: Offset(0, 18 - 36 * t), child: child),
            );
          },
          child: Icon(Icons.swipe_up, size: 38, color: kGreen, shadows: [
            Shadow(color: kGreen.withValues(alpha: 0.9), blurRadius: 14),
          ]),
        ),
      ),
    );
  }
}
