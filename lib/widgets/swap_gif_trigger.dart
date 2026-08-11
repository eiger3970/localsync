// widgets/swap_gif_trigger.dart
//
// 2026-08-17: sibling to ActionGif, for the case where the "at rest"
// state is a genuine separate static asset (an SVG rasterized to PNG
// at prep time - no flutter_svg dependency added, same reasoning as
// this app's earlier decision against it for cosmetic assets: pure
// vector art rasterizes once, no runtime SVG parsing needed) rather
// than a GIF's own first frame. Simpler than ControllableGif's manual
// frame-by-frame decoding: swapping between two different
// Image.asset providers is enough - Flutter starts a fresh
// ImageStream (and so the gif's own animation from its first frame)
// whenever the displayed asset changes, so no custom playback control
// is needed for the "restart from frame 0 every run" behavior. The
// _playCount-based key forces this even on a second trigger of the
// exact same gif path.
//
// Same timing contract as ActionGif (trigger() races a real action
// against the 2000ms floor; playThenRun() plays exactly 2000ms then
// calls an instant/sync action) - see that file's header comment for
// the full reasoning, identical here.

import 'package:flutter/material.dart';

class SwapGifTrigger extends StatefulWidget {
  final String staticAssetPath;
  final String animatedAssetPath;
  final double height;
  const SwapGifTrigger({
    super.key,
    required this.staticAssetPath,
    required this.animatedAssetPath,
    required this.height,
  });

  @override
  State<SwapGifTrigger> createState() => SwapGifTriggerState();
}

class SwapGifTriggerState extends State<SwapGifTrigger> {
  static const _minRun = Duration(milliseconds: 2000);
  bool _playing = false;
  int _runToken = 0;
  int _playCount = 0;

  bool get isPlaying => _playing;

  Future<void> trigger(Future<void> Function() action) async {
    if (_playing) return;
    final token = ++_runToken;
    setState(() {
      _playing = true;
      _playCount++;
    });
    await Future.wait([Future.delayed(_minRun), action()]);
    if (mounted && token == _runToken) setState(() => _playing = false);
  }

  Future<void> playThenRun(VoidCallback after) async {
    if (_playing) return;
    final token = ++_runToken;
    setState(() {
      _playing = true;
      _playCount++;
    });
    await Future.delayed(_minRun);
    if (mounted && token == _runToken) {
      setState(() => _playing = false);
      after();
    }
  }

  @override
  Widget build(BuildContext context) {
    return _playing
        ? Image.asset(
            widget.animatedAssetPath,
            key: ValueKey(_playCount),
            height: widget.height,
            filterQuality: FilterQuality.none,
          )
        : Image.asset(
            widget.staticAssetPath,
            height: widget.height,
            filterQuality: FilterQuality.none,
          );
  }
}
