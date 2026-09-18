// widgets/gif_swipe_trigger.dart
//
// 2026-08-14: extracted from home_screen.dart's private _GifSwipeTrigger
// so CommitScreen could use the exact same swipe-to-confirm mechanic for
// its own push, not a lookalike copy - "the button needs to not be a
// tap, but the consistency requires a swipe up for pushes... make the
// button something that's consistent with the main page's PUSH and gif
// swipe up." Behavior and layout unchanged from the original, just
// public and reusable.

import 'package:flutter/material.dart';
import '../theme.dart';
import 'action_gif.dart';
import 'sparkle_background.dart';
import 'triggerable_animation.dart';

class GifSwipeTrigger extends StatefulWidget {
  // 2026-09-17: nullable now - only required when animationBuilder
  // isn't given. Existing callers (CommitScreen, this file's other
  // home_screen.dart call sites) are unaffected, they always pass a
  // real asset path and never touch animationBuilder.
  final String? assetPath;
  final String caption;
  final bool swipeDown; // true = swipe down triggers, false = swipe up
  final double gifHeight;
  final bool alignTop;
  final Future<void> Function() onConfirm;
  // 2026-09-17: real ask, live - "Push pull flow, maybe on home screen
  // when pushing or pulling?" When given, replaces the hardcoded
  // ActionGif(assetPath: ...) in this widget's gif slot with whatever
  // this builds instead - the returned widget's State must implement
  // TriggerableAnimation. null (default) keeps the original ActionGif
  // behavior exactly as before.
  final Widget Function(Key key, double height)? animationBuilder;
  // 2026-08-14: "the screen immediately switches to the main screen, so
  // the gif shows for a split second. Then the main screen shows no
  // pushing gif, so that's a mismatch missing the flow of continuation"
  // - a caller that navigates away as soon as onConfirm's own Future
  // resolves cuts the animation off before its real 2000ms-minimum
  // floor (owned by ActionGif.trigger(), see that widget) has actually
  // played out, since that floor only delays when trigger() itself
  // resolves, not anything the caller does inside onConfirm. onSettled
  // fires after the whole trigger() - real action AND floor, whichever
  // is later - is truly done, so a caller that wants to navigate can
  // wait for the full, honest animation instead of just the network
  // call.
  final VoidCallback? onSettled;
  const GifSwipeTrigger({
    super.key,
    this.assetPath,
    required this.caption,
    required this.swipeDown,
    required this.gifHeight,
    this.alignTop = false,
    required this.onConfirm,
    this.onSettled,
    this.animationBuilder,
  }) : assert(assetPath != null || animationBuilder != null,
            'GifSwipeTrigger needs either assetPath or animationBuilder');

  @override
  State<GifSwipeTrigger> createState() => GifSwipeTriggerState();
}

// 2026-09-18: real ask, live - "Widget pull and push opened home screen
// but gifs weren't moving?" The Home Screen widget's Push/Pull buttons
// (and Quick Actions) call the real pull/push directly via
// pendingQuickAction, bypassing this widget's own swipe gesture
// entirely - the real sync ran, but nothing ever called _anim.trigger(),
// so the gif/flow animation never played. Was private
// (_GifSwipeTriggerState) - now public specifically so home_screen.dart
// can reach it through a GlobalKey<GifSwipeTriggerState> and call
// triggerConfirm() below, running the exact same visual flow a real
// swipe would without one.
class GifSwipeTriggerState extends State<GifSwipeTrigger> {
  static const _threshold = 56.0;
  // 2026-09-17: was GlobalKey<ActionGifState> - widened to the generic
  // State bound so this can hold either ActionGifState or a custom
  // animationBuilder's state, both accessed only through the shared
  // TriggerableAnimation interface below.
  final _gifKey = GlobalKey<State>();
  final _slotKey = GlobalKey();
  double _drag = 0;
  OverlayEntry? _overlayEntry;

  TriggerableAnimation? get _anim =>
      _gifKey.currentState as TriggerableAnimation?;
  bool get _playing => _anim?.isPlaying ?? false;

  Widget _buildSlotContent() => widget.animationBuilder != null
      ? widget.animationBuilder!(_gifKey, widget.gifHeight)
      : ActionGif(
          key: _gifKey,
          assetPath: widget.assetPath!,
          height: widget.gifHeight,
        );

  @override
  void dispose() {
    _overlayEntry?.remove();
    super.dispose();
  }

  void _onStart(DragStartDetails _) {
    if (_playing || _overlayEntry != null) return;
    final box = _slotKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final topLeft = box.localToGlobal(Offset.zero);
    final size = box.size;
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        left: topLeft.dx,
        top: topLeft.dy,
        width: size.width,
        height: size.height,
        child: IgnorePointer(
          child: Transform.translate(
            offset: Offset(0, _drag),
            child: _buildSlotContent(),
          ),
        ),
      ),
    );
    setState(() => _overlayEntry = entry);
    Overlay.of(context).insert(entry);
  }

  void _onUpdate(double delta) {
    if (_playing || _overlayEntry == null) return;
    _drag = widget.swipeDown
        ? (_drag + delta).clamp(0.0, double.infinity)
        : (_drag + delta).clamp(double.negativeInfinity, 0.0);
    _overlayEntry?.markNeedsBuild();
  }

  void _onEnd() {
    if (_overlayEntry == null) return;
    final reached = (widget.swipeDown ? _drag : -_drag) >= _threshold;
    _overlayEntry?.remove();
    setState(() {
      _overlayEntry = null;
      _drag = 0;
    });
    if (reached) _triggerConfirm();
  }

  void _triggerConfirm() {
    _anim?.trigger(widget.onConfirm).then((_) {
      if (mounted) widget.onSettled?.call();
    });
  }

  /// Runs the exact same animation-wrapped confirm flow a completed
  /// swipe gesture would, without one - for a caller that already has
  /// its own trigger (Quick Actions, the Home Screen widget's Push/Pull
  /// buttons) and needs the visual flow to actually play alongside it.
  /// No-ops while already playing, same guard _onEnd itself relies on.
  void triggerConfirm() {
    if (_playing) return;
    _triggerConfirm();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragStart: _onStart,
      onVerticalDragUpdate: (d) => _onUpdate(d.delta.dy),
      onVerticalDragEnd: (_) => _onEnd(),
      // 2026-08-23: third attempt at rounded corners here. The first
      // two (tight box w/ 10px padding + 20px radius, then a full-zone
      // card) both added extra black area beyond the gif+caption
      // content itself, which read as "too much black space" and got
      // reverted to square corners. This attempt uses a much smaller
      // radius (8px) and minimal padding (3px, just enough that the
      // rounded clip shaves the black background rather than visibly
      // cropping the gif's own square corner pixels) - far tighter
      // than the reverted 10px/20px version, not the whole zone.
      // Real risk, unconfirmed until on-device: 3px may still be too
      // little to fully clear the gif's corners depending on the
      // asset's actual edge content - watch for this specifically on
      // first real-device review.
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: widget.alignTop
              ? MainAxisAlignment.start
              : MainAxisAlignment.center,
          children: [
            if (widget.alignTop) const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: kVoid,
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    key: _slotKey,
                    height: widget.gifHeight,
                    child: _overlayEntry == null ? _buildSlotContent() : null,
                  ),
                  const SizedBox(height: 14),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      if (!_playing) const Positioned.fill(child: SparkleBackground()),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Text(widget.caption,
                            style: TextStyle(
                                color: kTextMid,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
