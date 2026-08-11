// widgets/controllable_gif.dart
//
// Minimal, dependency-free animated-GIF player with manual play/pause
// control. Flutter's plain Image widget auto-plays a GIF's own loop
// with no way to pause it - the swipe-triggered gifs across this app
// need the opposite (static at rest, only animating once a gesture
// actually triggers something), so this decodes the frames once via
// dart:ui's own codec API and steps through them on a plain Timer
// while playing, resting on frame 0 otherwise. No new package for
// something this small.

import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

class ControllableGif extends StatefulWidget {
  final String assetPath;
  final bool playing;
  final double height;
  const ControllableGif({
    super.key,
    required this.assetPath,
    required this.playing,
    required this.height,
  });

  @override
  State<ControllableGif> createState() => _ControllableGifState();
}

class _ControllableGifState extends State<ControllableGif> {
  List<ui.FrameInfo> _frames = const [];
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await rootBundle.load(widget.assetPath);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frames = <ui.FrameInfo>[];
    for (var i = 0; i < codec.frameCount; i++) {
      frames.add(await codec.getNextFrame());
    }
    if (!mounted) return;
    setState(() => _frames = frames);
    if (widget.playing) _scheduleNext();
  }

  @override
  void didUpdateWidget(covariant ControllableGif old) {
    super.didUpdateWidget(old);
    if (widget.playing && !old.playing) _scheduleNext();
    if (!widget.playing && old.playing) {
      _timer?.cancel();
      setState(() => _index = 0); // rest on the first frame
    }
  }

  void _scheduleNext() {
    if (_frames.isEmpty) return;
    _timer?.cancel();
    // dart:ui: a zero duration means "show indefinitely", not "advance
    // immediately" - none of this app's own gifs do that, but clamp
    // defensively rather than risk a zero-delay Timer loop if one ever
    // does.
    final duration = _frames[_index].duration;
    _timer = Timer(
      duration > Duration.zero ? duration : const Duration(milliseconds: 100),
      () {
        if (!mounted || !widget.playing) return;
        setState(() => _index = (_index + 1) % _frames.length);
        _scheduleNext();
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_frames.isEmpty) return SizedBox(height: widget.height);
    return RawImage(
      image: _frames[_index].image,
      height: widget.height,
      filterQuality: FilterQuality.none,
    );
  }
}
