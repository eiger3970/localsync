// widgets/brain_hero.dart
//
// 2026-09-26: welcome-screen hero - a glowing see-through brain (Blender
// render of a Royalty Free BlenderKit model, coloured by brain area).
//   idle        turns by itself; drag to turn it, tap to stop/start
//   success     plays once when the dog lands on the desktop: rainbow
//               stars climb the stem and the frontal lobe glows and grows
//   distracted  plays once when the drag misses: the frontal lobe dies
// Idle is 72 still frames (scrubbable by finger); the other two are
// animated WebP loops. Render script: ~/Documents/Blender/brain_render/.
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

enum BrainMode { idle, success, distracted }

class BrainHero extends StatefulWidget {
  final BrainMode mode;
  final int playId; // bump to replay success/distracted
  final VoidCallback onDone; // called when success/distracted finishes
  final double size;
  const BrainHero(
      {super.key,
      required this.mode,
      required this.playId,
      required this.onDone,
      this.size = 130});

  @override
  State<BrainHero> createState() => _BrainHeroState();
}

class _BrainHeroState extends State<BrainHero>
    with SingleTickerProviderStateMixin {
  static const _frames = 72;
  static const _fps = 24.0;
  static String _frame(int i) =>
      'assets/brain/idle/${(i % _frames + 1).toString().padLeft(4, '0')}.webp';

  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _f = 0;
  bool _paused = false;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((t) {
      final dt = (t - _last).inMicroseconds / 1e6;
      _last = t;
      if (widget.mode == BrainMode.idle && !_paused && !_dragging) {
        setState(() => _f = (_f + dt * _fps) % _frames);
      }
    })
      ..start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (var i = 0; i < _frames; i++) {
      precacheImage(AssetImage(_frame(i)), context);
    }
  }

  @override
  void didUpdateWidget(BrainHero old) {
    super.didUpdateWidget(old);
    if (widget.mode != BrainMode.idle && widget.playId != old.playId) {
      // Each loop is 72 frames at 24 fps = 3 s, then back to idle.
      final id = widget.playId;
      Future.delayed(const Duration(milliseconds: 3000), () {
        if (mounted && widget.playId == id) widget.onDone();
      });
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget image = switch (widget.mode) {
      BrainMode.idle => Image.asset(_frame(_f.floor()),
          gaplessPlayback: true, fit: BoxFit.contain),
      BrainMode.success => Image.asset('assets/brain/success.webp',
          key: ValueKey('s${widget.playId}'), fit: BoxFit.contain),
      BrainMode.distracted => Image.asset('assets/brain/distracted.webp',
          key: ValueKey('d${widget.playId}'), fit: BoxFit.contain),
    };
    return GestureDetector(
      onTap: () => setState(() => _paused = !_paused),
      onHorizontalDragStart: (_) => _dragging = true,
      onHorizontalDragUpdate: (d) =>
          setState(() => _f = (_f + d.delta.dx / 4) % _frames),
      onHorizontalDragEnd: (_) => _dragging = false,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient:
              RadialGradient(colors: [Color(0xFF1A1640), Color(0xFF03020A)]),
        ),
        child: image,
      ),
    );
  }
}
