// widgets/swap_gif_trigger.dart
//
// 2026-08-17: sibling to ActionGif, for the case where the "at rest"
// state is a genuine separate static asset rather than a GIF's own
// first frame. Same timing contract as ActionGif (trigger() races a
// real action against the 2000ms floor; playThenRun() plays exactly
// 2000ms then calls an instant/sync action) - see that file's header
// comment for the full reasoning, identical here.
//
// 2026-08-19: "AT REST: display dog_frame0.svg... not a rasterized
// stand-in" - the at-rest frame used to be a PNG rasterized from the
// SVG at prep time (avoiding flutter_svg for a cosmetic asset, per
// this app's earlier build-cost decision). Real device feedback: that
// 396x156 raster, nearest-neighbor scaled down ~5.6x for display,
// looked wrong compared to the source art. Swapped for DogFrame0
// (widgets/dog_frame0.dart) - a hand-rolled CustomPaint transcription
// of the SVG's own <rect>/<polyline> calls, still no flutter_svg
// dependency, but pixel-crisp at any size since nothing is resampled.
// staticAssetPath is gone - this widget is only ever used for the dog
// art pair (2 call sites, both linking_screen.dart), so there's no
// second static asset to be generic for.

import 'package:flutter/material.dart';
import 'dog_frame0.dart';

class SwapGifTrigger extends StatefulWidget {
  final String animatedAssetPath;
  final double height;
  const SwapGifTrigger({
    super.key,
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
        : DogFrame0(height: widget.height);
  }
}
