// widgets/shine_progress_bar.dart
//
// 2026-09-29: Ken - a solid green bar filling slowly can look frozen ("a
// classic Microsoft error where the computer would freeze and users
// wouldn't know"). Picked option B of the previews: a soft white shine
// glides across the green every 1.6 s, so the bar always visibly moves.
// "White or yellow pulse, not black - the app needs positivity."
import 'package:flutter/material.dart';

class ShineProgressBar extends StatefulWidget {
  final double value; // 0..1
  final Color color;
  final Color backgroundColor;
  final double height;
  const ShineProgressBar({
    super.key,
    required this.value,
    required this.color,
    required this.backgroundColor,
    this.height = 8,
  });

  @override
  State<ShineProgressBar> createState() => _ShineProgressBarState();
}

class _ShineProgressBarState extends State<ShineProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat();

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.height / 2),
      child: SizedBox(
        height: widget.height,
        child: ColoredBox(
          color: widget.backgroundColor,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: widget.value.clamp(0.0, 1.0),
              heightFactor: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(widget.height / 2),
                child: AnimatedBuilder(
                  animation: _sweep,
                  builder: (_, __) {
                    // Shine is 60 px wide and travels from just off the
                    // left edge to just off the right, eased like the
                    // preview.
                    final t = Curves.easeInOut.transform(_sweep.value);
                    return LayoutBuilder(builder: (_, c) {
                      const w = 60.0;
                      final left = -w + t * (c.maxWidth + w);
                      return Stack(children: [
                        Positioned.fill(child: ColoredBox(color: widget.color)),
                        Positioned(
                          left: left,
                          top: 0,
                          bottom: 0,
                          width: w,
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [
                                Color(0x00FFFFFF),
                                Color(0xD9FFFFFF),
                                Color(0x00FFFFFF),
                              ]),
                            ),
                          ),
                        ),
                      ]);
                    });
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
