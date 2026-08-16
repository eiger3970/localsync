// widgets/swap_gif_swipe_confirm.dart
//
// 2026-08-16: extracted from linking_screen.dart's private
// _SwapGifSwipeConfirm (introduced 2026-08-19 there) so PairingScreen's
// "CONTINUE - SET UP VAULT" button could use the same dog-on-a-leash
// swipe-to-confirm control instead of a plain tap ElevatedButton, per
// direct request to keep the app's confirm-action theme consistent
// rather than only using it in linking_screen.dart.
//
// This class owns the outer gesture detection, the drag/threshold
// decision, and the sparkle/label/error chrome; LeashSwipeConfirm itself
// just renders whatever drag state it's told and exposes the gif
// trigger.

import 'package:flutter/material.dart';
import '../theme.dart';
import 'leash_swipe_confirm.dart';
import 'sparkle_background.dart';

class SwapGifSwipeConfirm extends StatefulWidget {
  final String animatedAssetPath;
  final String? label;
  final VoidCallback onConfirm;
  final String? Function()? validate;
  const SwapGifSwipeConfirm({
    super.key,
    required this.animatedAssetPath,
    this.label,
    required this.onConfirm,
    this.validate,
  });

  @override
  State<SwapGifSwipeConfirm> createState() => SwapGifSwipeConfirmState();
}

class SwapGifSwipeConfirmState extends State<SwapGifSwipeConfirm> {
  static const _threshold = 64.0;
  final _gifKey = GlobalKey<LeashSwipeConfirmState>();
  String? _error;
  double _drag = 0;
  bool _springingBack = false;
  // 2026-08-19: resolved from this control's own actual available width
  // (via LayoutBuilder below) instead of a fixed constant, so the drag
  // clamp and the widget's own reserved width always agree with the
  // real screen. Placeholder until the first LayoutBuilder pass runs.
  double _maxDrag = 200;

  bool get _playing => _gifKey.currentState?.isPlaying ?? false;

  void _onUpdate(double delta) {
    if (_playing || _springingBack) return;
    setState(() => _drag = (_drag + delta).clamp(0.0, _maxDrag));
  }

  Future<void> _onEnd() async {
    if (_playing || _springingBack) return;
    final reached = _drag >= _threshold;
    final error = reached ? widget.validate?.call() : null;

    if (!reached || error != null) {
      setState(() {
        _error = error ?? _error;
        _drag = 0;
        _springingBack = true;
      });
      await Future.delayed(const Duration(milliseconds: 220));
      if (mounted) setState(() => _springingBack = false);
      return;
    }

    setState(() => _error = null);
    _gifKey.currentState?.playThenRun(widget.onConfirm);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _maxDrag = LeashSwipeConfirm.resolveMaxDrag(constraints.maxWidth);
        return GestureDetector(
          onHorizontalDragUpdate: (d) => _onUpdate(d.delta.dx),
          onHorizontalDragEnd: (_) => _onEnd(),
          child: SizedBox(
            width: double.infinity,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                if (!_playing) const Positioned.fill(child: SparkleBackground()),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LeashSwipeConfirm(
                      key: _gifKey,
                      animatedAssetPath: widget.animatedAssetPath,
                      dragAmount: _drag,
                      maxDrag: _maxDrag,
                      threshold: _threshold,
                      snappingBack: _springingBack,
                      height: 70,
                    ),
                    if (widget.label != null) ...[
                      const SizedBox(height: 8),
                      Text(widget.label!,
                          style: const TextStyle(
                              color: kTextMid,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1)),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!,
                          style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
