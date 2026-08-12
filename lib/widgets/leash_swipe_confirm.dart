// widgets/leash_swipe_confirm.dart
//
// 2026-08-19: swipe-confirm control built around the final 3-asset
// split - progress_person.svg, progress_dog.svg, progress_running.gif
// (252x132, exactly progress_dog.svg's own bounding box, dog-only, no
// baked-in person - confirmed by diffing all 4 frames: every pixel in
// the canvas changes frame to frame, unlike the earlier gif export
// which had a second, static copy of the person baked in alongside the
// dog and needed cropping to avoid doubling the person up. Not needed
// this round - the gif can be shown full-frame.)
//
// The person (PersonFigure) is fixed and vector-drawn at the left edge
// - it never moves and never becomes a gif. The dog (DogFigure) is the
// actual draggable element, vector-drawn at rest, connected to the
// person by a leash that's a plain code-drawn rectangle (not baked
// into either SVG) whose width AND color track the live drag distance:
// grey normally, red once the drag passes ~78% of the way to the
// caller's threshold, back to grey if it retreats.
//
// On release past threshold: the leash does one brief, one-time fade
// (the "snap"), then the dog SVG is replaced by progress_running.gif,
// looping in place at wherever the dog was dragged to - not reset back
// near the person.
//
// Same minimum-2000ms / no-maximum / reset-safe-token timing contract
// as ActionGif/SwapGifTrigger - see action_gif.dart's header comment
// for the full reasoning, identical here.

import 'package:flutter/material.dart';
import 'progress_person.dart';
import 'progress_dog.dart';
import 'controllable_gif.dart';

// Shared between this widget and its caller (linking_screen.dart's
// gesture detector needs the same ceiling so the two don't drift).
const kLeashMaxDrag = 120.0;

const _leashGrey = Color(0xFFcfd6de);
const _leashRed = Color(0xFFef4444);
const _leashWarningRatio = 0.78;

class LeashSwipeConfirm extends StatefulWidget {
  final String animatedAssetPath;
  final double height;
  // Live drag distance (0..kLeashMaxDrag) - the caller owns the
  // GestureDetector and threshold decision; this widget only renders
  // whatever it's told and exposes the gif trigger.
  final double dragAmount;
  // The caller's own snap threshold - used only to compute the leash's
  // grey/red warning color (dragAmount as a fraction of this), not for
  // any trigger decision of this widget's own.
  final double threshold;
  // True only for the brief window after an invalid (below-threshold)
  // release, while the dog animates back to its resting position -
  // switches the position/width/color tweens from instant (duration:
  // 0, tracking the finger 1:1) to a real animated duration.
  final bool snappingBack;
  const LeashSwipeConfirm({
    super.key,
    required this.animatedAssetPath,
    required this.dragAmount,
    required this.threshold,
    this.snappingBack = false,
    this.height = 70,
  });

  @override
  State<LeashSwipeConfirm> createState() => LeashSwipeConfirmState();
}

class LeashSwipeConfirmState extends State<LeashSwipeConfirm> {
  static const _minRun = Duration(milliseconds: 2000);
  static const _snapDuration = Duration(milliseconds: 150);
  static const _springDuration = Duration(milliseconds: 220);
  static const _restGap = 20.0;

  bool _playing = false;
  bool _snappingLeash = false; // brief pre-gif leash-break fade
  int _runToken = 0;

  bool get isPlaying => _playing;

  /// Plays the leash-snap, then the gif, for at least 2000ms, then
  /// calls [after] - mirrors SwapGifTrigger.playThenRun (see that
  /// file's header / action_gif.dart for the full contract). Token-
  /// gated so a stale run can't fire after a fresh one starts.
  Future<void> playThenRun(VoidCallback after) async {
    if (_playing) return;
    final token = ++_runToken;

    setState(() => _snappingLeash = true);
    await Future.delayed(_snapDuration);
    if (!mounted || token != _runToken) return;

    setState(() {
      _snappingLeash = false;
      _playing = true;
    });
    await Future.delayed(_minRun);
    if (mounted && token == _runToken) {
      setState(() => _playing = false);
      after();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rowHeight = widget.height;
    final personWidth =
        rowHeight * PersonFigure.sourceWidth / PersonFigure.sourceHeight;
    final dogWidth =
        rowHeight * DogFigure.sourceWidth / DogFigure.contentHeight;
    final dogLeft = personWidth + _restGap + widget.dragAmount;
    final leashWidth = _restGap + widget.dragAmount;
    final tweenDuration =
        widget.snappingBack ? _springDuration : Duration.zero;
    final warningRatio =
        widget.threshold <= 0 ? 0.0 : widget.dragAmount / widget.threshold;
    final leashColor =
        warningRatio >= _leashWarningRatio ? _leashRed : _leashGrey;

    return SizedBox(
      height: rowHeight,
      // Reserve width for the farthest possible drag so the control's
      // footprint never reflows mid-drag.
      width: personWidth + _restGap + kLeashMaxDrag + dogWidth,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: personWidth,
            top: rowHeight / 2 - 1.5,
            child: AnimatedOpacity(
              duration: _snapDuration,
              opacity: (_playing || _snappingLeash) ? 0.0 : 1.0,
              child: AnimatedContainer(
                duration: tweenDuration,
                width: leashWidth,
                height: 3,
                color: leashColor,
              ),
            ),
          ),
          Positioned(left: 0, top: 0, child: PersonFigure(height: rowHeight)),
          AnimatedPositioned(
            duration: tweenDuration,
            curve: Curves.easeOut,
            left: dogLeft,
            top: 0,
            child: _playing
                ? ControllableGif(
                    assetPath: widget.animatedAssetPath,
                    playing: true,
                    height: rowHeight,
                  )
                : DogFigure(height: rowHeight),
          ),
        ],
      ),
    );
  }
}
