// widgets/key_pairing_trigger.dart
//
// Drag-to-pair gesture for PairingScreen: pairing_phone_key.svg is freely
// draggable anywhere within a generous play area and locks in the moment
// it's dropped near pairing_laptop_lock.svg's matching keyway - not a
// constrained single-axis slider. Same overall contract as
// GifSwipeTrigger/ActionGif (drag -> snap -> race a real async action
// against a minimum floor so the result never flashes too briefly).
//
// 2026-08-16: rebuilt from a horizontal-only slider (drag distance capped
// at the resting gap between the two SVGs, which meant the key could
// never physically reach the keyway - "only drags slightly to the right,
// then glows green") into true free 2D drag with distance-based success,
// per direct feedback: "should be able to drag anywhere on the screen as
// human users like to play and learn, and when the user drags over the
// computer lock, success."

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme.dart';
import 'sparkle_background.dart';

class KeyPairingTrigger extends StatefulWidget {
  final Future<void> Function() onConfirm;
  final VoidCallback? onSettled;
  final bool enabled;
  final String runningLabel;
  // 2026-08-16: "moving phonekey to the right will allow badge 2 to be
  // on the left of the 2 images" - rendered by this widget itself
  // (rather than positioned externally, e.g. by ContentAboveDragCanvas)
  // so it can be pixel-aligned against the key/lock's actual rest row
  // instead of a guessed offset from outside.
  final Widget? leadingBadge;
  const KeyPairingTrigger({
    super.key,
    required this.onConfirm,
    this.onSettled,
    this.enabled = true,
    this.runningLabel = 'REGISTERING KEY…',
    this.leadingBadge,
  });

  @override
  State<KeyPairingTrigger> createState() => _KeyPairingTriggerState();
}

class _KeyPairingTriggerState extends State<KeyPairingTrigger>
    with SingleTickerProviderStateMixin {
  static const _keyWidth = 110.0;
  static const _lockWidth = 176.0;
  // 2026-08-16: was a fixed 240 - direct feedback that the key "only
  // drags around its own square area" wanted the actual full remaining
  // screen space, not just a bigger fixed box. Now takes whatever height
  // the caller's layout hands it (both screens now wrap this in Expanded
  // instead of a SingleChildScrollView), with 240 kept only as a
  // fallback for the (untested) case of unbounded constraints.
  static const _fallbackCanvasHeight = 240.0;
  static const _edgePad = 8.0;
  // 2026-08-16: "Badges 1 and 2 need to be vertically aligned" - badge 1
  // (in the caller's own content) sits at x=24, matching that screen's
  // Padding.all(24); this widget's own canvas only had 8px of edge
  // padding (_edgePad), so badge 2 was rendering 16px further left than
  // badge 1. _badgeLeft matches the caller's content padding explicitly
  // instead of reusing _edgePad, which is a different, unrelated margin
  // (the canvas's own right-edge/lock margin).
  static const _badgeLeft = 24.0;
  static const _badgeSize = 24.0;
  static const _badgeGap = 12.0;
  // Reserved to the left of the key's rest position when leadingBadge is
  // set - the badge's own left inset, its width, and a gap.
  static const _badgeReserve = _badgeLeft + _badgeSize + _badgeGap - _edgePad;
  // 2026-08-16: "the images are down near the bottom" - the pair used to
  // sit vertically centered within the whole (now very tall) canvas,
  // which put it far below the content and the leading badge instead of
  // right next to them. Anchored near the top of the canvas instead -
  // the draggable area (see _clamp) still spans the full canvas height,
  // only the idle/rest position moved.
  static const _pairRowTop = _edgePad + 12;

  // Where each SVG's tooth pattern actually sits relative to its own
  // widget's top-left corner, derived from both assets' viewBox/transform
  // math (both cut paths share raw path origin (129,79)).
  static const _keyOriginFromLeft = 30.57;
  static const _lockOriginFromLeft = 15.84;
  static const _keyHeight = _keyWidth * 90 / 145; // ~68.28
  static const _lockHeight = _lockWidth * 250 / 260; // ~169.23
  // Vertical gap between the two tooth-pattern origins when both SVGs are
  // simply centered in the same canvas - the two assets' art isn't
  // centered identically within their own viewBoxes, so this isn't
  // derivable from _keyHeight/_lockHeight alone; verified by rendering
  // both at these exact display widths and checking pixel alignment.
  // Independent of canvas height (both centering offsets move together).
  static const _verticalNudge = -10.5;

  static const _successRadius = 44.0; // generous - "not too difficult"
  static const _minRun = Duration(milliseconds: 2000);

  late final AnimationController _snapCtrl;
  Offset _drag = Offset.zero; // offset from rest position
  bool _dragging = false;
  bool _snapped = false; // sitting exactly in the lock, glow stays on
  bool _running = false; // pairing in flight - gesture locked out

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    super.dispose();
  }

  Offset _target(double canvasWidth, double keyRestLeft) {
    final lockLeft = canvasWidth - _lockWidth - _edgePad;
    final targetLeft = lockLeft + _lockOriginFromLeft - (keyRestLeft + _keyOriginFromLeft);
    return Offset(targetLeft, _verticalNudge);
  }

  // 2026-08-16: "Phone key drag is limited to left bottom square area, is
  // whole screen not viable?" - it was, unintentionally: the
  // GestureDetector only wrapped the key's own small visual footprint
  // (~110x68), so a drag could only be *started* by touching exactly
  // where the key currently sat, not anywhere in the canvas. Rebuilt
  // around a single canvas-wide GestureDetector (see build()) using
  // absolute pointer position instead of incremental deltas from the
  // key's prior spot - touch down anywhere in the play area and the key
  // jumps under your finger immediately, matching "whole screen."
  Offset _keyPosFromPointer(
      Offset localPosition, double keyRestLeft, double keyRestTop) {
    return Offset(
      localPosition.dx - keyRestLeft - _keyWidth / 2,
      localPosition.dy - keyRestTop - _keyHeight / 2,
    );
  }

  void _onStart(DragStartDetails d, double canvasWidth, double canvasHeight,
      double keyRestLeft, double keyRestTop) {
    if (_running || !widget.enabled) return;
    // 2026-08-16: "keyboard appears and now I can't see the phonekey
    // image at the bottom of the screen... unable to progress" -
    // dismiss the keyboard the moment a drag starts so the canvas always
    // has the full screen to work with, not just whatever's left above
    // the keyboard.
    FocusScope.of(context).unfocus();
    setState(() {
      _dragging = true;
      _snapped = false;
      _drag = _clamp(_keyPosFromPointer(d.localPosition, keyRestLeft, keyRestTop),
          canvasWidth, canvasHeight, keyRestLeft, keyRestTop);
    });
  }

  void _onUpdate(DragUpdateDetails d, double canvasWidth, double canvasHeight,
      double keyRestLeft, double keyRestTop) {
    if (!_dragging) return;
    setState(() {
      _drag = _clamp(_keyPosFromPointer(d.localPosition, keyRestLeft, keyRestTop),
          canvasWidth, canvasHeight, keyRestLeft, keyRestTop);
    });
    // Live hit-test - success fires the moment the key is dragged over the
    // lock, no need to lift a finger precisely on target.
    if ((_drag - _target(canvasWidth, keyRestLeft)).distance <= _successRadius) {
      _dragging = false;
      _snap(canvasWidth, keyRestLeft);
    }
  }

  void _onEnd(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    _animateTo(Offset.zero);
  }

  Offset _clamp(Offset o, double canvasWidth, double canvasHeight, double keyRestLeft,
      double keyRestTop) {
    final minDx = _edgePad - keyRestLeft;
    final maxDx = canvasWidth - _keyWidth - _edgePad - keyRestLeft;
    // 2026-08-16: "phonekey drag cannot go up" - real bug, not the same
    // one as before: this used -_pairRowTop (~20) instead of -keyRestTop
    // (~70, since the key's own rest row sits partway down the taller
    // lock's height, not flush with the canvas top) - so upward drag was
    // clamped after only ~20px of travel instead of reaching the actual
    // top of the canvas. Bounds are relative to the key's own rest
    // position, so they need the key's own rest top, not the pair row's.
    final minDy = -keyRestTop;
    final maxDy = canvasHeight - _keyHeight - keyRestTop;
    return Offset(o.dx.clamp(minDx, maxDx), o.dy.clamp(minDy, maxDy));
  }

  void _snap(double canvasWidth, double keyRestLeft) {
    setState(() => _snapped = true);
    _animateTo(_target(canvasWidth, keyRestLeft)).then((_) => _startPairing());
  }

  Future<void> _animateTo(Offset target) async {
    final from = _drag;
    _snapCtrl
      ..value = 0
      ..reset();
    final anim = Tween<Offset>(begin: from, end: target).animate(
      CurvedAnimation(parent: _snapCtrl, curve: Curves.easeOutCubic),
    );
    void listener() => setState(() => _drag = anim.value);
    anim.addListener(listener);
    await _snapCtrl.forward();
    anim.removeListener(listener);
    _drag = target;
  }

  Future<void> _startPairing() async {
    setState(() => _running = true);
    await Future.wait([Future.delayed(_minRun), widget.onConfirm()]);
    if (!mounted) return;
    setState(() {
      _running = false;
      _snapped = false;
    });
    await _animateTo(Offset.zero);
    widget.onSettled?.call();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final canvasWidth = constraints.maxWidth;
      final canvasHeight =
          constraints.maxHeight.isFinite ? constraints.maxHeight : _fallbackCanvasHeight;
      final lockLeft = canvasWidth - _lockWidth - _edgePad;
      final lockTop = _pairRowTop;
      final keyRestLeft =
          _edgePad + (widget.leadingBadge != null ? _badgeReserve : 0);
      final keyRestTop = _pairRowTop + (_lockHeight - _keyHeight) / 2;
      final active = _running || _snapped;

      return SizedBox(
        height: canvasHeight,
        width: canvasWidth,
        child: Stack(
          // 2026-08-16: real device bug - "only moves a millimetre and
          // stops, only drags properly on 2nd attempt." Root cause: the
          // sparkle hint below is conditionally present/absent (gated on
          // !_dragging), sitting BETWEEN the lock and the key in this
          // list. With no explicit Keys, the instant a drag starts and
          // the first setState fires, the sparkle entry disappears and
          // the key's Positioned+GestureDetector shifts from index 2 to
          // index 1 - Flutter can't tell that's the same widget moved,
          // not a new one, so it tears down and recreates the
          // GestureDetector's element (and its live gesture recognizer)
          // mid-drag. Explicit Keys on every child make identity
          // survive the shuffle regardless of list position.
          children: [
            if (widget.leadingBadge != null)
              Positioned(
                key: const ValueKey('leadingBadge'),
                left: _badgeLeft,
                top: _pairRowTop + (_lockHeight - _badgeSize) / 2,
                child: widget.leadingBadge!,
              ),
            // Lock painted first (bottom) at its fixed position - opaque
            // canvas, so anything painted before it here would vanish
            // wherever the key later overlaps it.
            Positioned(
              key: const ValueKey('lock'),
              left: lockLeft,
              top: lockTop,
              width: _lockWidth,
              child: _PulsingLock(
                active: active,
                child: SvgPicture.asset(
                  'assets/pairing/pairing_laptop_lock.svg',
                  width: _lockWidth,
                ),
              ),
            ),
            // Idle affordance - only while there's nothing else to look at.
            if (widget.enabled && !_dragging && !_running && !_snapped)
              Positioned(
                key: const ValueKey('sparkle'),
                left: keyRestLeft - 30,
                top: keyRestTop - 30,
                width: _keyWidth + 60,
                height: _keyHeight + 60,
                child: const SparkleBackground(),
              ),
            // Key - purely visual now, the gesture layer below owns all
            // touch handling so it can grab the key from anywhere in the
            // canvas, not just this small box.
            Positioned(
              key: const ValueKey('key'),
              left: keyRestLeft + _drag.dx,
              top: keyRestTop + _drag.dy,
              width: _keyWidth,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _running ? 0.55 : (widget.enabled ? 1 : 0.35),
                  duration: const Duration(milliseconds: 200),
                  child: SvgPicture.asset(
                    'assets/pairing/pairing_phone_key.svg',
                    width: _keyWidth,
                  ),
                ),
              ),
            ),
            if (_running)
              Positioned(
                key: const ValueKey('runningLabel'),
                bottom: 4,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    widget.runningLabel,
                    style: const TextStyle(
                        color: kTextDim, fontSize: 11, letterSpacing: 1.5),
                  ),
                ),
              ),
            // Gesture layer spans the whole canvas (not just the key's own
            // footprint) so touching down anywhere grabs the key and
            // brings it to your finger, instead of requiring the first
            // touch to land exactly on the key's current position.
            Positioned.fill(
              key: const ValueKey('dragSurface'),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (d) =>
                    _onStart(d, canvasWidth, canvasHeight, keyRestLeft, keyRestTop),
                onPanUpdate: (d) =>
                    _onUpdate(d, canvasWidth, canvasHeight, keyRestLeft, keyRestTop),
                onPanEnd: _onEnd,
              ),
            ),
          ],
        ),
      );
    });
  }
}

// Soft green glow behind the lock once the key has seated / while pairing
// runs - the SVGs themselves are static, this is the only "it's live" cue.
class _PulsingLock extends StatefulWidget {
  final bool active;
  final Widget child;
  const _PulsingLock({required this.active, required this.child});

  @override
  State<_PulsingLock> createState() => _PulsingLockState();
}

class _PulsingLockState extends State<_PulsingLock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: kGreen.withOpacity(0.15 + 0.15 * _ctrl.value),
              blurRadius: 24,
              spreadRadius: 4,
            ),
          ],
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}
