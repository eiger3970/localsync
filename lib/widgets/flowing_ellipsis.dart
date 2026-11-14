import 'dart:async';

import 'package:flutter/material.dart';

// 2026-11-14: owner - "I prefer the flowing ellips, easier on the eye". One waiting effect for the whole app:
// the label stays still and 1-3 dots flow after it. Unused dots are transparent so the text never jumps.
// Pass the label without trailing dots ('Desktop syncing', not 'Desktop syncing...').
class FlowingEllipsis extends StatefulWidget {
  final String label;
  final TextStyle? style;
  final TextAlign? textAlign;
  const FlowingEllipsis(this.label, {super.key, this.style, this.textAlign});

  static String strip(String s) => s.replaceFirst(RegExp(r'(\.\.\.|…)\s*$'), '');

  @override
  State<FlowingEllipsis> createState() => _FlowingEllipsisState();
}

class _FlowingEllipsisState extends State<FlowingEllipsis> {
  Timer? _tick;
  int _dots = 1;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (mounted) setState(() => _dots = _dots % 3 + 1);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: FlowingEllipsis.strip(widget.label)),
        TextSpan(text: '.' * _dots),
        TextSpan(text: '.' * (3 - _dots), style: const TextStyle(color: Colors.transparent)),
      ]),
      style: widget.style,
      textAlign: widget.textAlign,
    );
  }
}
