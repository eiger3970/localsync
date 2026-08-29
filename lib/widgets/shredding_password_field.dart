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
  // 2026-08-25: real feedback, live - "stars should only be on the left
  // of the text... left of the D." A prefixIcon is the real Flutter
  // mechanism for "icon to the left of the field's text" - Positioned
  // hacks with SparkleBackground (built for open backgrounds, scatters
  // 12 fixed positions across whatever width it's given) were fighting
  // the field's own layout instead of using it. Caller-controlled, not
  // always-on - "field 2 have stars once field1 has typing started" -
  // field 1 passes true always, field 2 passes a reactive condition.
  final bool showSparkle;
  // 2026-08-28: real feedback, live - "Step 2 activates but then I have
  // to tap the field, why doesn't the cursor activate ready to type?"
  // Stage 2 unlocks dynamically (after Stage 1 settles + consent is
  // answered), well after this widget's own initial build - a plain
  // `autofocus: true` only fires on first mount, it wouldn't catch that
  // later unlock. Caller-controlled FocusNode instead, so
  // linking_screen.dart can call requestFocus() at the exact moment
  // Stage 2 actually becomes usable.
  final FocusNode? focusNode;
  const ShreddingPasswordField({
    super.key,
    required this.controller,
    this.enabled = true,
    this.showSparkle = false,
    this.focusNode,
  });

  @override
  State<ShreddingPasswordField> createState() => ShreddingPasswordFieldState();
}

class ShreddingPasswordFieldState extends State<ShreddingPasswordField>
    with TickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 650);
  final _rand = Random();
  late final AnimationController _ctrl;
  // 2026-08-26: real feedback, live - "stars need to be twinkling." The
  // prefixIcon cluster below was two static Icons with no animation at
  // all, unlike SparkleBackground's real twinkle (sine-wave opacity,
  // looping). Same sine formula, just driven by its own controller and
  // scoped to this small 28px cluster instead of a full-width canvas.
  //
  // 2026-08-26, follow-up: real feedback, live - "twinkle isn't random,
  // the left star is permanent and the other blinks on and off, but the
  // randomness is the goal." One shared controller with a fixed 0.5
  // phase offset put the two stars exactly opposite each other on the
  // same period - a smooth, perfectly predictable seesaw, not
  // independent twinkling, and every field instance twinkled in lockstep
  // with every other. Two separate controllers with different (non-
  // integer-ratio) periods drift in and out of phase continuously
  // instead of repeating a fixed short pattern, and a per-instance
  // random start phase (picked once here, not derived from the shared
  // controller) means field 1 and field 2 never mirror each other
  // either.
  late final AnimationController _sparkleCtrl;
  late final AnimationController _sparkleCtrl2;
  late final double _phaseSeed1;
  late final double _phaseSeed2;
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
    _phaseSeed1 = _rand.nextDouble();
    _phaseSeed2 = _rand.nextDouble();
    _sparkleCtrl =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))
          ..repeat();
    _sparkleCtrl2 =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 1900))
          ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _sparkleCtrl.dispose();
    _sparkleCtrl2.dispose();
    super.dispose();
  }

  double _twinkle(AnimationController ctrl, double phaseSeed) {
    final phase = (ctrl.value + phaseSeed) % 1.0;
    return sin(phase * pi * 2) * 0.5 + 0.5;
  }

  /// Plays the shred animation on whatever text is currently in the
  /// field, then clears it. No-op if the field is already empty.
  Future<void> shred() async {
    final text = widget.controller.text;
    if (text.isEmpty || _shredding) return;
    _shreddedText = text;
    _drift = List.generate(
        text.length,
        (_) =>
            Offset(_rand.nextDouble() * 50 - 25, 30 + _rand.nextDouble() * 26));
    _rotation = List.generate(
        text.length, (_) => (_rand.nextDouble() * 140 - 70) * pi / 180);
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
            focusNode: widget.focusNode,
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
              // 2026-08-25: "stars need more stars" - a single icon read
              // as too sparse. A small cluster (2 sizes, slight offset)
              // reads as sparkle rather than one static glyph, still via
              // prefixIcon so it stays left-of-text with no manual
              // positioning.
              // 2026-08-28: real feedback, live - "the fade away blue
              // stars on the password fields can be removed, it's out
              // of time." Reverted the fade-to-blue treatment (had its
              // own real timing/amplitude bugs across several rounds) -
              // plain hard on/off via widget.showSparkle directly, same
              // as before that whole detour. The stop-condition itself
              // (_field1Done in linking_screen.dart) stays - that part
              // was confirmed working.
              prefixIcon: widget.showSparkle
                  ? AnimatedBuilder(
                      animation: Listenable.merge([_sparkleCtrl, _sparkleCtrl2]),
                      builder: (_, __) => SizedBox(
                        width: 28,
                        // 2026-08-26: real feedback, live, three times now
                        // - "lower the twinkly stars a little." First
                        // attempt used top-padding (cancelled out by
                        // prefixIcon's own centering). Second used
                        // Transform.translate(0, 5). Third doubled to 10.
                        // Still "a little" more each time - bumped again
                        // to 16.
                        child: Transform.translate(
                          offset: const Offset(0, 16),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(Icons.auto_awesome,
                                  color: kGreen.withValues(
                                      alpha: _twinkle(_sparkleCtrl, _phaseSeed1)),
                                  size: 16),
                              Positioned(
                                left: 14,
                                top: 2,
                                child: Icon(Icons.auto_awesome,
                                    color: kGreen.withValues(
                                        alpha: _twinkle(_sparkleCtrl2, _phaseSeed2)),
                                    size: 10),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : null,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                  child: Wrap(
                    children: List.generate(_shreddedText.length, (i) {
                      final t = ((_ctrl.value - _delay[i]) / (1 - _delay[i]))
                          .clamp(0.0, 1.0);
                      return Transform.translate(
                        offset: _drift[i] * t,
                        child: Transform.rotate(
                          angle: _rotation[i] * t,
                          child: Opacity(
                            opacity: 1 - t,
                            child: Text(_obscure ? '•' : _shreddedText[i],
                                style: TextStyle(color: kGreen, fontSize: 16)),
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
