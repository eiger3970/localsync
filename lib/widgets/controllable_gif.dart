// widgets/controllable_gif.dart
//
// Minimal, dependency-free animated-GIF player with manual play/pause
// control. Flutter's plain Image widget auto-plays a GIF's own loop
// with no way to pause it - the swipe-triggered gifs across this app
// need the opposite (static at rest, only animating once a gesture
// actually triggers something), so this decodes the frames once via
// dart:ui's own codec API and steps through them on a Ticker while
// playing (see _startTicking's own 2026-09-22 comment for why a Ticker,
// not a plain Timer), resting on frame 0 otherwise. No new package for
// something this small.
//
// 2026-08-20: optional frameDurationOverrides added for
// dog_success_stand.gif - "the timing leaves the standing dog jumping
// in the air" - the file's own baked-in timing gives its longest hold
// to a jump/lean pose right before the loop wraps, not a standing one.
// This overrides specific decoded frames' display duration without
// touching the source gif at all - null (every other call site) uses
// the file's own per-frame durations unchanged.

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;

class ControllableGif extends StatefulWidget {
  final String assetPath;
  final bool playing;
  final double height;
  final Map<int, Duration>? frameDurationOverrides;
  const ControllableGif({
    super.key,
    required this.assetPath,
    required this.playing,
    required this.height,
    this.frameDurationOverrides,
  });

  @override
  State<ControllableGif> createState() => _ControllableGifState();
}

class _ControllableGifState extends State<ControllableGif>
    with SingleTickerProviderStateMixin {
  List<ui.FrameInfo> _frames = const [];
  int _index = 0;
  Ticker? _ticker;
  Duration _lastTick = Duration.zero;
  Duration _elapsedInFrame = Duration.zero;

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
    if (widget.playing) _startTicking();
  }

  @override
  void didUpdateWidget(covariant ControllableGif old) {
    super.didUpdateWidget(old);
    if (widget.playing && !old.playing) _startTicking();
    if (!widget.playing && old.playing) {
      _ticker?.stop();
      setState(() => _index = 0); // rest on the first frame
    }
  }

  // 2026-09-22: real feedback, live - "the dog froze rather than
  // running. I tapped the frozen dog and it ran." (leash_swipe_confirm.
  // dart, first construction with playing:true, not a later toggle).
  // Root cause: a raw Timer + setState() drives the timer callback
  // correctly, but is NOT hooked into the rendering pipeline's own
  // vsync-driven frame scheduling the way an AnimationController/Ticker
  // is - a well-documented Flutter footgun where a Timer-only "advance
  // and setState" loop can silently fail to produce an actual painted
  // frame under some real-device conditions, needing some UNRELATED
  // interaction (a tap causing its own frame request) to surface the
  // change that had already technically happened in state. A Ticker
  // ties frame-stepping directly to the same vsync callback mechanism
  // real Flutter animations use, guaranteeing what setState() changes
  // actually gets painted on the very next frame, every time.
  void _startTicking() {
    if (_frames.isEmpty) return;
    _lastTick = Duration.zero;
    _elapsedInFrame = Duration.zero;
    _ticker?.dispose();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    _elapsedInFrame += elapsed - _lastTick;
    _lastTick = elapsed;
    // dart:ui: a zero duration means "show indefinitely", not "advance
    // immediately" - none of this app's own gifs do that, but clamp
    // defensively rather than risk a zero-duration frame never
    // advancing.
    final frameDuration =
        widget.frameDurationOverrides?[_index] ?? _frames[_index].duration;
    final effective = frameDuration > Duration.zero
        ? frameDuration
        : const Duration(milliseconds: 100);
    if (_elapsedInFrame >= effective) {
      _elapsedInFrame -= effective;
      setState(() => _index = (_index + 1) % _frames.length);
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    // 2026-09-18: real bug, live - "sometimes the app is now closing,
    // is that a performance issue?" Every decoded frame is a real
    // dart:ui.Image holding native bitmap memory - Dart's own GC
    // doesn't reliably reclaim that promptly on its own, it needs an
    // explicit dispose() call. This widget never made one, so every
    // ControllableGif that unmounted (a SnackBar closing, a rebuild
    // creating a fresh instance) leaked its whole decoded frame set.
    // This session added more create/dispose churn than before (the
    // success dog gif now shows on every Desktop sync completion,
    // FlowBehindGif wraps a real ActionGif alongside the flow layer) -
    // surfacing a pre-existing leak more visibly, not a new one.
    for (final frame in _frames) {
      frame.image.dispose();
    }
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
