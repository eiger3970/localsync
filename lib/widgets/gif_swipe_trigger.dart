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

class GifSwipeTrigger extends StatefulWidget {
  final String assetPath;
  final String caption;
  final bool swipeDown; // true = swipe down triggers, false = swipe up
  final double gifHeight;
  final bool alignTop;
  final Future<void> Function() onConfirm;
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
    required this.assetPath,
    required this.caption,
    required this.swipeDown,
    required this.gifHeight,
    this.alignTop = false,
    required this.onConfirm,
    this.onSettled,
  });

  @override
  State<GifSwipeTrigger> createState() => _GifSwipeTriggerState();
}

class _GifSwipeTriggerState extends State<GifSwipeTrigger> {
  static const _threshold = 56.0;
  final _gifKey = GlobalKey<ActionGifState>();
  final _slotKey = GlobalKey();
  double _drag = 0;
  OverlayEntry? _overlayEntry;

  bool get _playing => _gifKey.currentState?.isPlaying ?? false;

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
            child: ActionGif(
              key: _gifKey,
              assetPath: widget.assetPath,
              height: widget.gifHeight,
            ),
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
    if (reached) {
      _gifKey.currentState?.trigger(widget.onConfirm).then((_) {
        if (mounted) widget.onSettled?.call();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragStart: _onStart,
      onVerticalDragUpdate: (d) => _onUpdate(d.delta.dy),
      onVerticalDragEnd: (_) => _onEnd(),
      // 2026-08-22: two rounds of real feedback on this. First: a
      // blanket `color: kVoid` across the whole zone blocked
      // main.dart's global FlagBackdrop (bold skins' tiled mini-
      // flags) entirely - "the gifs need to be seen, so flags should
      // not be over the moving gifs" led to putting it back, but that
      // made bold Home visually identical to subtle Home again -
      // "screen_home_bold is wrong and is screen_home_subtle." Real
      // problem with both: this zone isn't uniformly "gif" or
      // uniformly "empty" - the gif+caption block (fixed height) sits
      // inside an Expanded that's taller than it (especially PUSH,
      // which centers rather than pins to top), leaving genuine empty
      // margin around it. Opaque fill now wraps ONLY that inner
      // content block (tight, not double.infinity), not the whole
      // zone - the gif/caption stay fully protected, the real margin
      // around them shows the bold pattern same as everywhere else.
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
              color: kVoid,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    key: _slotKey,
                    height: widget.gifHeight,
                    child: _overlayEntry == null
                        ? ActionGif(
                            key: _gifKey,
                            assetPath: widget.assetPath,
                            height: widget.gifHeight,
                          )
                        : null,
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
