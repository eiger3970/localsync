// widgets/key_pairing_trigger.dart
//
// Drag-to-pair gesture for PairingScreen: pairing_phone_key.svg slides
// right into pairing_laptop_lock.svg's matching keyway. Same overall
// contract as GifSwipeTrigger/ActionGif (drag past a threshold ->
// snap -> race a real async action against a minimum floor so the
// result never flashes too briefly) but horizontal, and driven by two
// static SVGs plus a snap animation rather than a looping gif, since
// there's no gif asset for this gesture yet.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme.dart';

class KeyPairingTrigger extends StatefulWidget {
  final Future<void> Function() onConfirm;
  final VoidCallback? onSettled;
  final bool enabled;
  const KeyPairingTrigger({
    super.key,
    required this.onConfirm,
    this.onSettled,
    this.enabled = true,
  });

  @override
  State<KeyPairingTrigger> createState() => _KeyPairingTriggerState();
}

class _KeyPairingTriggerState extends State<KeyPairingTrigger>
    with SingleTickerProviderStateMixin {
  static const _keyWidth = 110.0;
  static const _lockWidth = 176.0;
  static const _gap = 18.0;
  static const _maxDrag = _gap; // phone slides across the gap to meet the lock
  static const _minRun = Duration(milliseconds: 2000);

  late final AnimationController _snapCtrl;
  double _dragStart = 0;
  double _drag = 0; // 0 (resting) .. _maxDrag (flush against the lock)
  bool _dragging = false;
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

  void _onStart(DragStartDetails d) {
    if (_running || !widget.enabled) return;
    _dragging = true;
    _dragStart = _drag;
  }

  void _onUpdate(DragUpdateDetails d) {
    if (!_dragging) return;
    setState(() {
      _drag = (_dragStart + d.delta.dx).clamp(0.0, _maxDrag);
      _dragStart = _drag; // running accumulator for the next incremental delta
    });
  }

  void _onEnd(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    final reached = _drag >= _maxDrag * 0.8;
    if (reached) {
      _animateTo(_maxDrag).then((_) => _startPairing());
    } else {
      _animateTo(0);
    }
  }

  Future<void> _animateTo(double target) async {
    final from = _drag;
    _snapCtrl
      ..value = 0
      ..reset();
    final anim = Tween<double>(begin: from, end: target).animate(
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
    setState(() => _running = false);
    await _animateTo(0);
    widget.onSettled?.call();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _drag / _maxDrag; // 0..1
    return SizedBox(
      height: 190,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // phone_key sits flush against the lock once dragged/paired -
              // no fixed gap SizedBox here, _drag itself provides the motion.
              Transform.translate(
                offset: Offset(_drag, 0),
                child: GestureDetector(
                  onHorizontalDragStart: _onStart,
                  onHorizontalDragUpdate: _onUpdate,
                  onHorizontalDragEnd: _onEnd,
                  child: SizedBox(
                    width: _keyWidth,
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
              ),
              const SizedBox(width: _gap),
              SizedBox(
                width: _lockWidth,
                child: _PulsingLock(
                  active: _running || progress >= 0.999,
                  child: SvgPicture.asset(
                    'assets/pairing/pairing_laptop_lock.svg',
                    width: _lockWidth,
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            bottom: 4,
            child: Text(
              _running
                  ? 'REGISTERING KEY…'
                  : (widget.enabled
                      ? 'DRAG THE KEY INTO THE LOCK'
                      : 'TYPE THE PASSWORD FIRST'),
              style: const TextStyle(
                  color: kTextDim, fontSize: 11, letterSpacing: 1.5),
            ),
          ),
        ],
      ),
    );
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
