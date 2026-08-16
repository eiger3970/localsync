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
  const KeyPairingTrigger({
    super.key,
    required this.onConfirm,
    this.onSettled,
    this.enabled = true,
    this.runningLabel = 'REGISTERING KEY…',
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
  Offset _dragStart = Offset.zero;
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

  Offset _target(double canvasWidth) {
    final lockLeft = canvasWidth - _lockWidth - _edgePad;
    final targetLeft = lockLeft + _lockOriginFromLeft - (_edgePad + _keyOriginFromLeft);
    return Offset(targetLeft, _verticalNudge);
  }

  void _onStart(DragStartDetails d) {
    if (_running || !widget.enabled) return;
    // setState here (not just on the first update) so the sparkle hint
    // is removed from the tree on touch-down, before any movement -
    // keeps the Stack's child list settled for the whole gesture instead
    // of changing shape one frame into the drag.
    setState(() {
      _dragging = true;
      _snapped = false;
      _dragStart = _drag;
    });
  }

  void _onUpdate(DragUpdateDetails d, double canvasWidth, double canvasHeight) {
    if (!_dragging) return;
    setState(() {
      _drag = _clamp(_dragStart + d.delta, canvasWidth, canvasHeight);
      _dragStart = _drag;
    });
    // Live hit-test - success fires the moment the key is dragged over the
    // lock, no need to lift a finger precisely on target.
    if ((_drag - _target(canvasWidth)).distance <= _successRadius) {
      _dragging = false;
      _snap(canvasWidth);
    }
  }

  void _onEnd(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    _animateTo(Offset.zero);
  }

  Offset _clamp(Offset o, double canvasWidth, double canvasHeight) {
    final minDx = -_edgePad;
    final maxDx = canvasWidth - _keyWidth - _edgePad;
    final minDy = -(canvasHeight - _keyHeight) / 2;
    final maxDy = (canvasHeight - _keyHeight) / 2;
    return Offset(o.dx.clamp(minDx, maxDx), o.dy.clamp(minDy, maxDy));
  }

  void _snap(double canvasWidth) {
    setState(() => _snapped = true);
    _animateTo(_target(canvasWidth)).then((_) => _startPairing());
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
      final lockTop = (canvasHeight - _lockHeight) / 2;
      final keyRestLeft = _edgePad;
      final keyRestTop = (canvasHeight - _keyHeight) / 2;
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
            // Key painted second (on top) so it can slide anywhere,
            // including across the lock's own canvas, without vanishing
            // behind it.
            Positioned(
              key: const ValueKey('key'),
              left: keyRestLeft + _drag.dx,
              top: keyRestTop + _drag.dy,
              width: _keyWidth,
              child: GestureDetector(
                onPanStart: _onStart,
                onPanUpdate: (d) => _onUpdate(d, canvasWidth, canvasHeight),
                onPanEnd: _onEnd,
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
