// widgets/content_above_drag_canvas.dart
//
// 2026-08-16: extracted after the Positioned.fill background approach
// (introduced this session to fix KeyPairingTrigger's "drag only in
// bottom left corner" bug) caused a real regression - "PAIR WITH
// DESKTOP is messed up with images now over the top area with text."
// A full-bleed canvas vertically centered in the *whole screen*
// inevitably overlaps whatever text content sits at the top, since
// nothing was reserving that space.
//
// Fix: measure the content's actual rendered height after each frame
// (GlobalKey + addPostFrameCallback) and position the canvas to start
// exactly below it - not a guessed fixed offset, the real number. Same
// technique used at both KeyPairingTrigger call sites (PairingScreen,
// linking_screen.dart's failed-setup view), so it's shared here instead
// of duplicated.

import 'package:flutter/material.dart';

class ContentAboveDragCanvas extends StatefulWidget {
  final Widget content;
  final Widget canvas;
  // Pinned to the very bottom, e.g. a CANCEL button - measured the same
  // way so the canvas doesn't run underneath it either.
  final Widget? bottomPinned;
  const ContentAboveDragCanvas({
    super.key,
    required this.content,
    required this.canvas,
    this.bottomPinned,
  });

  @override
  State<ContentAboveDragCanvas> createState() => _ContentAboveDragCanvasState();
}

class _ContentAboveDragCanvasState extends State<ContentAboveDragCanvas> {
  final _contentKey = GlobalKey();
  final _bottomKey = GlobalKey();
  double _contentHeight = 0;
  double _bottomHeight = 0;

  @override
  Widget build(BuildContext context) {
    // Re-measure after every frame - cheap (a size lookup, no layout
    // work of its own) and correctly tracks content that changes height
    // across rebuilds (e.g. a failure box appearing/disappearing).
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());

    return Stack(
      children: [
        Positioned(
          top: _contentHeight,
          left: 0,
          right: 0,
          bottom: _bottomHeight,
          child: widget.canvas,
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: KeyedSubtree(key: _contentKey, child: widget.content),
        ),
        if (widget.bottomPinned != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: KeyedSubtree(key: _bottomKey, child: widget.bottomPinned!),
          ),
      ],
    );
  }

  void _measure() {
    final h = _contentKey.currentContext?.size?.height ?? 0;
    final bh = _bottomKey.currentContext?.size?.height ?? 0;
    if ((h - _contentHeight).abs() > 0.5 || (bh - _bottomHeight).abs() > 0.5) {
      if (!mounted) return;
      setState(() {
        _contentHeight = h;
        _bottomHeight = bh;
      });
    }
  }
}
