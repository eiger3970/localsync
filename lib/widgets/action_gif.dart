// widgets/action_gif.dart
//
// 2026-08-16: the reusable component this app's various gif triggers
// (pull, push, I'VE CREATED IT, SYNCLOCAL HOME) all needed - built to
// match a specific timing contract:
//
//  1. Idle: shows only the static first frame, not animating.
//  2. Trigger: the caller's own gesture (swipe up/down/right, tap -
//     that detection is the caller's job, not this widget's) calls
//     trigger(action), which starts the loop.
//  3. Minimum run time: animates for at least 2000ms from the moment
//     it starts, even if [action] finishes faster.
//  4. No maximum: if [action] takes longer than 2000ms, keeps looping
//     until it actually finishes - no timeout, no auto-stop.
//  5. Completion: [action]'s own Future completing is the sole signal
//     that ends the run (subject to the 2000ms floor in #3) - nothing
//     else stops it early.
//  6. Reset safety: each trigger() call gets its own token. If, for
//     whatever reason, trigger() were ever called again on the same
//     instance while a previous run is still in flight, a late
//     completion from that stale run can't stop the newer one.
//
// Built on ControllableGif (this file's sibling) for the actual frame
// playback - this layer owns only the timing contract above.

import 'package:flutter/material.dart';
import 'controllable_gif.dart';

class ActionGif extends StatefulWidget {
  final String assetPath;
  final double height;
  const ActionGif({super.key, required this.assetPath, required this.height});

  @override
  State<ActionGif> createState() => ActionGifState();
}

class ActionGifState extends State<ActionGif> {
  static const _minRun = Duration(milliseconds: 2000);
  bool _playing = false;
  int _runToken = 0;

  bool get isPlaying => _playing;

  /// Starts the animation and runs [action], not stopping until both
  /// the 2000ms floor has elapsed AND [action] has completed -
  /// whichever finishes later. No-ops if a run is already in flight.
  Future<void> trigger(Future<void> Function() action) async {
    if (_playing) return;
    final token = ++_runToken;
    setState(() => _playing = true);
    await Future.wait([Future.delayed(_minRun), action()]);
    if (mounted && token == _runToken) setState(() => _playing = false);
  }

  @override
  Widget build(BuildContext context) => ControllableGif(
        assetPath: widget.assetPath,
        playing: _playing,
        height: widget.height,
      );
}
