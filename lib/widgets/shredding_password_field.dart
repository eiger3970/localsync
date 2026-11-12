// widgets/shredding_password_field.dart
//
// The desktop password is typed once and never stored (see
// PairingController) - this widget makes that promise visible instead
// of just stating it in a caption. Call shred() the moment pairing
// actually starts (not on submit alone - only once the key registration
// is genuinely underway) and the typed text fades out instead of just
// clearing, then the field resets for a retry if pairing fails.

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../theme.dart';
import 'password_mismatch_marks.dart';

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
  // 2026-08-30: real device bug, screenshots confirmed - the confirm-
  // password field (linking_screen.dart) wraps this in its own
  // AnimatedContainer border that turns red/green to show match state,
  // but this field's OWN default focused border (theme.dart's
  // InputDecorationTheme.focusedBorder, kGreen for every text field in
  // the app) kept drawing too - a visible double ring whenever the two
  // disagreed (red outside from a mismatch, green inside from just
  // being focused), reading as one clean border only when they
  // happened to both be green. False lets a caller that already
  // provides its own validation border suppress this field's default
  // one instead of the two competing silently.
  final bool showOwnBorder;
  // 2026-09-09: real feedback, live - "after I enter password field1, I
  // need to scroll down to the hidden password field2... a new user
  // [might not] figure this out." Neither field had any keyboard
  // action wired at all - the only way to reach field 2 was already
  // knowing to blind-scroll past the open keyboard to find and tap it.
  // textInputAction/onSubmitted are the standard Flutter "Next" keyboard
  // button mechanism - optional, null by default, so any other caller
  // of this widget is unaffected.
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  /// 2026-11-12 owner: the confirm field passes the first password here. Wrong characters get a red underline (the
  /// first one a highlight) drawn over the field's own dots; the characters themselves show only when the user taps
  /// the eye. Null = no marks and the old layout.
  final String? markAgainst;

  /// Port of the website's ConfirmEmailInput `first` prop: true for the first password field, whose partner may be
  /// unfinished, so it only reports once the two lengths are within 1.
  final bool markIsFirst;
  const ShreddingPasswordField({
    this.markAgainst,
    this.markIsFirst = false,
    super.key,
    required this.controller,
    this.enabled = true,
    this.showSparkle = false,
    this.focusNode,
    this.showOwnBorder = true,
    this.textInputAction,
    this.onSubmitted,
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

  // 2026-11-12 owner: wrong-character marks are a port of the website's confirm_email_input.tsx (+ email_mismatch.ts):
  // every differing character is UNDERLINED live; when focus moves INTO a field the suspect characters turn
  // HIGHLIGHTED and the first is selected, so the next key replaces it. Typing drops back to underline unless the key
  // replaced exactly the highlighted character. The marks only settle after SETTLE_MS without typing in either field.
  static const _settleMs = 350;
  static const _armMs = 1500;
  Timer? _armT;
  FocusNode? _ownFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());
  bool _armed = false;
  DateTime _focusAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastIn = DateTime.fromMillisecondsSinceEpoch(0); // focus-time selections must never fire after typing started
  Timer? _settleT;
  String _sv = '', _sw = '', _prev = '', _ctlText = '';
  String _sig = '';

  @override
  void initState() {
    super.initState();
    _sv = _prev = _ctlText = widget.controller.text;
    _sw = widget.markAgainst ?? '';
    widget.controller.addListener(_onCtl);
    _focus.addListener(_onFocus);
    _ctrl = AnimationController(vsync: this, duration: _duration);
    _phaseSeed1 = _rand.nextDouble();
    _phaseSeed2 = _rand.nextDouble();
    _sparkleCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1300))
      ..repeat();
    _sparkleCtrl2 = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1900))
      ..repeat();
  }

  @override
  void didUpdateWidget(ShreddingPasswordField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.markAgainst != widget.markAgainst) _scheduleSettle();
  }

  void _scheduleSettle() {
    _settleT?.cancel();
    _settleT = Timer(const Duration(milliseconds: _settleMs), () {
      if (!mounted) return;
      setState(() {
        _sv = widget.controller.text;
        _sw = widget.markAgainst ?? '';
      });
    });
    // 2026-11-12 owner: "highlight the current field the cursor is live, when the typing has finished" - but the
    // first version armed after 350 ms and the next key overwrote a character while the user was still typing
    // (test@mest.co). The highlight now waits for a real pause.
    _armT?.cancel();
    _armT = Timer(const Duration(milliseconds: _armMs), () {
      if (!mounted) return;
      if (_focus.hasFocus && widget.markAgainst != null) setState(() => _armed = true);
    });
  }

  void _onCtl() {
    if (widget.controller.text == _ctlText) return; // selection-only change
    _ctlText = widget.controller.text;
    _scheduleSettle();
  }

  void _onFocus() {
    if (widget.markAgainst == null) return;
    if (_focus.hasFocus) {
      _focusAt = DateTime.now();
      setState(() => _armed = true);
      void early() {
        if (!_lastIn.isAfter(_focusAt)) _sel();
      }
      Future.delayed(const Duration(milliseconds: 40), early);
      Future.delayed(const Duration(milliseconds: 160), early);
    } else {
      setState(() => _armed = false);
    }
  }

  /// (mismatch, marked positions, finished) for [value] against the partner field. 2026-11-12 owner: underlines stay
  /// until resolved, so every differing character in the overlap is marked at all times. [finished] = both texts have
  /// settled and are within one character of each other, the only time a highlight (and the select-to-replace) may
  /// happen, so a half-typed field is never overwritten.
  (Mismatch?, List<int>, bool) _calc(String value) {
    final w = widget.markAgainst ?? '';
    if (value.isEmpty || w.isEmpty || value == w) return (null, const [], false);
    final settled = _sv == value && _sw == w;
    // a focused field that is shorter than its partner is probably still being typed: never highlight it
    final finished = settled && (value.length - w.length).abs() <= 1 && !(_focus.hasFocus && value.length < w.length);
    if (finished) {
      final full = textMismatch(value, w);
      if (full != null) {
        if (full.kind == MismatchKind.sub) {
          return (full, [for (var i = 0; i < value.length; i++) if (i < w.length && value[i] != w[i]) i], true);
        }
        return (full, [full.idx], true);
      }
    }
    final subs = [for (var i = 0; i < value.length && i < w.length; i++) if (value[i] != w[i]) i];
    if (subs.isEmpty) return (null, const [], false);
    return (Mismatch(MismatchKind.sub, subs.first), subs, finished);
  }

  void _sel() {
    if (!mounted || !_focus.hasFocus || widget.markAgainst == null) return;
    final c = widget.controller;
    final (mm, marks, finished) = _calc(c.text);
    if (mm == null || marks.isEmpty || !finished) return;
    final h = marks.first.clamp(0, c.text.length);
    c.selection = TextSelection(
        baseOffset: h,
        extentOffset: mm.kind == MismatchKind.missing ? h : (h + 1).clamp(0, c.text.length));
  }

  void _onChanged(String nv) {
    _lastIn = DateTime.now();
    // a typed letter that replaces exactly the highlighted one: stay armed, so the next suspect character is
    // highlighted and selected. Any other edit drops back to underline.
    final (_, marks, _) = _calc(_prev);
    final h = marks.isEmpty ? null : marks.first;
    final replacedHot = _armed &&
        h != null &&
        nv.length == _prev.length &&
        h < nv.length &&
        nv[h] != _prev[h] &&
        [for (var i = 0; i < nv.length; i++) if (i != h) nv[i] == _prev[i]].every((x) => x);
    if (!replacedHot) _armed = false;
    _prev = nv;
  }

  @override
  void dispose() {
    _settleT?.cancel();
    _armT?.cancel();
    widget.controller.removeListener(_onCtl);
    _focus.removeListener(_onFocus);
    _ownFocus?.dispose();
    _ctrl.dispose();
    _sparkleCtrl.dispose();
    _sparkleCtrl2.dispose();
    super.dispose();
  }

  double _twinkle(AnimationController ctrl, double phaseSeed) {
    final phase = (ctrl.value + phaseSeed) % 1.0;
    return sin(phase * pi * 2) * 0.5 + 0.5;
  }

  /// Fades out whatever text is currently in the field, then clears it.
  /// No-op if the field is already empty.
  Future<void> shred() async {
    if (widget.controller.text.isEmpty || _shredding) return;
    setState(() => _shredding = true);
    await _ctrl.forward(from: 0);
    widget.controller.clear();
    if (mounted) setState(() => _shredding = false);
    _ctrl.reset();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => Opacity(opacity: 1 - _ctrl.value, child: child),
      child: _withMarks(context, TextField(
        key: _fieldKey,
        controller: widget.controller,
        focusNode: _focus,
        onChanged: widget.markAgainst == null ? null : _onChanged,
        onTap: widget.markAgainst == null
            ? null
            : () {
                if (DateTime.now().difference(_focusAt).inMilliseconds < 500 && !_lastIn.isAfter(_focusAt)) Future(_sel);
              },
        obscureText: _obscure,
        enabled: widget.enabled && !_shredding,
        textInputAction: widget.textInputAction,
        onSubmitted: widget.onSubmitted,
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
          border: widget.showOwnBorder ? null : InputBorder.none,
          enabledBorder: widget.showOwnBorder ? null : InputBorder.none,
          focusedBorder: widget.showOwnBorder ? null : InputBorder.none,
          disabledBorder: widget.showOwnBorder ? null : InputBorder.none,
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
                                    alpha:
                                        _twinkle(_sparkleCtrl2, _phaseSeed2)),
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
      )),
    );
  }

  // the website's mismatch colour (#f59e0b): amber, never red
  static const _amber = Color(0xFFF59E0B);

  final _fieldKey = GlobalKey();
  final _stackKey = GlobalKey();
  List<Rect> _rects = const [];

  /// 2026-11-12 owner: the marks sit exactly on the field's own characters. Their rectangles are read from the
  /// TextField's RenderEditable (so any font, size, prefix icon or scale lines up) instead of being guessed.
  void _measure(List<int> idx) {
    if (!mounted) return;
    EditableTextState? es;
    void visit(Element e) {
      if (es != null) return;
      if (e is StatefulElement && e.state is EditableTextState) {
        es = e.state as EditableTextState;
        return;
      }
      e.visitChildren(visit);
    }

    _fieldKey.currentContext?.visitChildElements(visit);
    final box = _stackKey.currentContext?.findRenderObject();
    final out = <Rect>[];
    if (es != null && box is RenderBox && box.hasSize) {
      final re = es!.renderEditable;
      for (final i in idx) {
        if (i < 0 || i >= widget.controller.text.length) continue;
        final bs = re.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
        if (bs.isEmpty) continue;
        out.add(MatrixUtils.transformRect(re.getTransformTo(box), bs.first.toRect()));
      }
    }
    if (out.length != _rects.length || [for (var i = 0; i < out.length; i++) out[i] != _rects[i]].contains(true)) {
      setState(() => _rects = out);
    }
  }

  Widget _withMarks(BuildContext context, TextField field) {
    if (widget.markAgainst == null) return field;
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (_, __) {
        final typed = widget.controller.text;
        final (mm, marks, finished) = _calc(typed);
        final hot = _armed && finished && mm != null;
        // the characters to mark: a missing character is shown on its two neighbours, dashed
        final idx = mm == null
            ? <int>[]
            : mm.kind == MismatchKind.missing
                ? [mm.idx - 1, mm.idx]
                : marks;
        final sig = '$hot|${mm?.kind}|${idx.join(',')}|$_sv|$_sw|$typed|$_obscure';
        if (sig != _sig) {
          _sig = sig;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _measure(idx);
            if (hot && _focus.hasFocus) _sel();
          });
        }
        // The Stack is always returned: swapping the bare field for a Stack re-creates the TextField, which drops
        // focus and hides the keyboard mid-edit.
        return Stack(key: _stackKey, children: [
          field,
          if (idx.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _MarkPainter(_rects, hot, mm?.kind == MismatchKind.missing, _amber),
                ),
              ),
            )
          else
            const SizedBox.shrink(),
        ]);
      },
    );
  }
}

/// Underline under every marked character; the highlight (focused field once typing has finished) is a translucent
/// amber block over it, so the character stays readable.
class _MarkPainter extends CustomPainter {
  final List<Rect> rects;
  final bool hot, dashed;
  final Color color;
  _MarkPainter(this.rects, this.hot, this.dashed, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    for (var n = 0; n < rects.length; n++) {
      final r = rects[n];
      if (hot && n == 0) {
        // only the FIRST wrong character is highlighted; the others stay underlined until the highlight reaches them
        canvas.drawRRect(RRect.fromRectAndRadius(r.inflate(1), const Radius.circular(2)),
            Paint()..color = color.withValues(alpha: 0.4));
        continue;
      }
      final y = r.bottom + 1;
      final p = Paint()
        ..color = color
        ..strokeWidth = 3;
      if (dashed) {
        for (var x = r.left; x < r.right; x += 6) {
          canvas.drawLine(Offset(x, y), Offset((x + 3).clamp(r.left, r.right), y), p);
        }
      } else {
        canvas.drawLine(Offset(r.left, y), Offset(r.right, y), p);
      }
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.rects != rects || old.hot != hot || old.dashed != dashed;
}
