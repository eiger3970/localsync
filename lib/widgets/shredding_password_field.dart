// widgets/shredding_password_field.dart
//
// The desktop password is typed once and never stored (see
// PairingController) - this widget makes that promise visible instead
// of just stating it in a caption. Call shred() the moment pairing
// actually starts (not on submit alone - only once the key registration
// is genuinely underway) and the typed characters fly apart instead of
// just clearing, then the field resets for a retry if pairing fails.

import 'dart:math';
import 'package:flutter/material.dart';
import '../theme.dart';

class ShreddingPasswordField extends StatefulWidget {
  final TextEditingController controller;
  final bool enabled;
  const ShreddingPasswordField({
    super.key,
    required this.controller,
    this.enabled = true,
  });

  @override
  State<ShreddingPasswordField> createState() => ShreddingPasswordFieldState();
}

class ShreddingPasswordFieldState extends State<ShreddingPasswordField>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 650);
  final _rand = Random();
  late final AnimationController _ctrl;
  bool _obscure = true;
  bool _shredding = false;
  String _shreddedText = '';
  List<Offset> _drift = const [];
  List<double> _rotation = const [];
  List<double> _delay = const [];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _duration);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Plays the shred animation on whatever text is currently in the
  /// field, then clears it. No-op if the field is already empty.
  Future<void> shred() async {
    final text = widget.controller.text;
    if (text.isEmpty || _shredding) return;
    _shreddedText = text;
    _drift = List.generate(
        text.length, (_) => Offset(_rand.nextDouble() * 50 - 25, 30 + _rand.nextDouble() * 26));
    _rotation = List.generate(text.length, (_) => (_rand.nextDouble() * 140 - 70) * pi / 180);
    _delay = List.generate(text.length, (i) => i / text.length * 0.35);
    setState(() => _shredding = true);
    await _ctrl.forward(from: 0);
    widget.controller.clear();
    if (mounted) setState(() => _shredding = false);
    _ctrl.reset();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Opacity(
          opacity: _shredding ? 0 : 1,
          child: TextField(
            controller: widget.controller,
            obscureText: _obscure,
            enabled: widget.enabled && !_shredding,
            style: TextStyle(color: kStar),
            // 2026-08-16: "this is a strong white as though is a solid
            // immutable text... should change to a faded text which is
            // a typical hint" - labelText renders bold and floats above
            // the field permanently once focused/filled, reading as
            // fixed content rather than a placeholder. hintText actually
            // disappears once typing starts, matching a real hint.
            //
            // 2026-08-16, follow-up: "too small and dark, I can't read
            // it" - the theme's shared hintStyle (kTextDim, 12px) is
            // fine for a lightweight aside but too dim/small to read
            // comfortably as the only label this field has. Overridden
            // locally rather than changed in theme.dart, since other
            // fields' hints weren't flagged and shouldn't shift too.
            decoration: InputDecoration(
              hintText: 'Desktop password…',
              hintStyle: TextStyle(color: kTextMid, fontSize: 14),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
        ),
        if (_shredding)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (_, __) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                  child: Wrap(
                    children: List.generate(_shreddedText.length, (i) {
                      final t = ((_ctrl.value - _delay[i]) / (1 - _delay[i])).clamp(0.0, 1.0);
                      return Transform.translate(
                        offset: _drift[i] * t,
                        child: Transform.rotate(
                          angle: _rotation[i] * t,
                          child: Opacity(
                            opacity: 1 - t,
                            child: Text(_obscure ? '•' : _shreddedText[i],
                                style: TextStyle(color: kBlue, fontSize: 16)),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
