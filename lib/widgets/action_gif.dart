// widgets/action_gif.dart
//
// 2026-08-16: the reusable component this app's various gif triggers
// (pull, push, LOCALSYNC HOME) all needed - built to match a specific
// timing contract:
//
//  1. Idle: shows only the static first frame, not animating.
//  2. Trigger: the caller's own gesture (swipe up/down/right, tap -
//     that detection is the caller's job, not this widget's) calls
//     trigger(action) or playThenRun(after), which starts the loop.
//  3. Minimum run time: animates for at least 2000ms from the moment
//     it starts, even if the real action finishes faster.
//  4. No maximum: if the real action takes longer than 2000ms, keeps
//     looping until it actually finishes - no timeout, no auto-stop.
//  5. Completion: for trigger(), [action]'s own Future completing is
//     the sole signal that ends the run (subject to the 2000ms floor).
//  6. Reset safety: each call gets its own token, so a late completion
//     from a stale run can't stop a newer one.
//
// Two entry points for two different kinds of "action":
// - trigger(action): races the 2000ms floor against a real async
//   operation with unknown duration (a network pull/push) - stops
//   once BOTH are done, whichever is later. Nothing else happens
//   after; the caller shows its own result separately (e.g. a
//   SnackBar) since there's no "next screen" this leads into.
// - playThenRun(after): plays for exactly the 2000ms floor, THEN
//   calls [after] - for actions that are an instant/synchronous
//   transition (closing this screen, confirming a step) where racing
//   would let the transition fire immediately and cut the animation
//   off before it's been visibly seen. 2026-08-17 fix: this was
//   missing - _GifSwipeConfirm previously used trigger() even for
//   instant Navigator.pop()/confirm calls, so the real transition
//   fired the instant the gesture registered, not after the animation
//   played ("action the gif at frame 0 and then run for >=2000ms then
//   action the next action" - it wasn't sequenced that way before).
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

  /// Races the 2000ms floor against [action]'s own completion - stops
  /// once both are done. No-ops if a run is already in flight.
  Future<void> trigger(Future<void> Function() action) async {
    if (_playing) return;
    final token = ++_runToken;
    setState(() => _playing = true);
    await Future.wait([Future.delayed(_minRun), action()]);
    if (mounted && token == _runToken) setState(() => _playing = false);
  }

  /// Plays for exactly the 2000ms floor, then calls [after] - for
  /// instant/synchronous actions with no real async work to race
  /// against (a screen transition, a confirm callback).
  Future<void> playThenRun(VoidCallback after) async {
    if (_playing) return;
    final token = ++_runToken;
    setState(() => _playing = true);
    await Future.delayed(_minRun);
    if (mounted && token == _runToken) {
      setState(() => _playing = false);
      after();
    }
  }

  @override
  Widget build(BuildContext context) => ControllableGif(
        assetPath: widget.assetPath,
        playing: _playing,
        height: widget.height,
      );
}
