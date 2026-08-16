// screens/pairing_screen.dart
//
// One-time pairing: enter the desktop's login password to install this
// phone's SSH key. Password is never stored - only held in this screen's
// local state for the duration of the request.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../features/linking/linking_state.dart';
import '../features/linking/linking_controller.dart';
import '../features/pairing/pairing_controller.dart';
import '../widgets/diag_card.dart';
import '../widgets/key_pairing_trigger.dart';
import '../widgets/shredding_password_field.dart';
import 'linking_screen.dart';

class PairingScreen extends StatefulWidget {
  final String desktopUser;
  final String desktopIp;
  const PairingScreen({
    super.key,
    required this.desktopUser,
    required this.desktopIp,
  });

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  late final PairingController _ctrl;
  final _passwordCtrl = TextEditingController();
  final _shredKey = GlobalKey<ShreddingPasswordFieldState>();

  @override
  void initState() {
    super.initState();
    _ctrl = PairingController(
      desktopUser: widget.desktopUser,
      desktopIp:   widget.desktopIp,
    );
    _ctrl.addListener(_onChange);
    _passwordCtrl.addListener(_onChange);
  }

  void _onChange() => setState(() {});

  @override
  void dispose() {
    _ctrl.removeListener(_onChange);
    _ctrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = _ctrl.result;

    if (result is StepSuccess) {
      return Scaffold(
        appBar: AppBar(title: const Text('PAIR WITH DESKTOP')),
        body: _PairedSuccessView(
          onContinue: () => _continueToVaultSetup(context),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('PAIR WITH DESKTOP')),
      // 2026-08-16: rebuilt from one long SingleChildScrollView (which
      // squeezed the key/lock drag gesture into a small fixed box and
      // put it inside the same Scrollable that was stealing early
      // vertical-drag events - "I have to drag down and then the
      // phonekey drags up") into: a scrollable strip for the text/status
      // content up top, then a plain (non-scrolling) Expanded area below
      // it that hands the drag widget the actual remaining screen space
      // to roam in, with no ancestor Scrollable competing for the
      // gesture.
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Connect to ${widget.desktopUser}@${widget.desktopIp}',
                        style: const TextStyle(
                            color: kStar, fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 16),
                      // 2026-08-16: "this is verbose and needs to be
                      // simplified. Can you design an infographic for
                      // this workflow process?" - replaced the
                      // type-once/never-stored paragraph with a 3-step
                      // icon strip. No new asset pipeline needed (reuses
                      // Material icons in the app's existing palette) -
                      // glanceable in one look instead of a sentence to
                      // parse.
                      const _PasswordWorkflowStrip(),
                      const SizedBox(height: 24),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _StepBadge(1),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ShreddingPasswordField(
                              key: _shredKey,
                              controller: _passwordCtrl,
                              enabled: !_ctrl.isRunning,
                            ),
                          ),
                        ],
                      ),
                      if (result is StepFailure) ...[
                        const SizedBox(height: 20),
                        // 2026-08-16: was a bespoke Container using
                        // kTextDim at 14px for the resolution text -
                        // direct feedback that it was "too small and
                        // dark to read." Switched to the same DiagCard
                        // used everywhere else in the app (kStar, 15px,
                        // 1.7 line height) instead of inventing a
                        // dimmer, harder-to-read variant just for this
                        // screen.
                        DiagCard(
                          label: 'WHAT HAPPENED',
                          text: result.diagnosis,
                          accent: Colors.redAccent,
                        ),
                        const SizedBox(height: 12),
                        DiagCard(
                          label: 'HOW TO FIX IT',
                          text: result.resolution,
                          accent: kGreen,
                        ),
                        // 2026-08-16: guards against both null AND an
                        // empty/whitespace-only debugDetail - real device
                        // feedback showed the "Raw error" label with
                        // nothing underneath it, which a bare null-check
                        // wouldn't have caught if the underlying
                        // exception's toString() ever comes back blank.
                        if (result.debugDetail != null &&
                            result.debugDetail!.trim().isNotEmpty) ...[
                          const SizedBox(height: 12),
                          DiagCard(
                            label: 'RAW ERROR (TEMPORARY DIAGNOSTIC)',
                            text: result.debugDetail!,
                            accent: Colors.redAccent,
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // 2026-08-16: replaced the old "Type your password, then
              // drag the key..." sentence entirely - direct feedback
              // that it was too verbose and users prefer the visuals to
              // carry the instruction. The step-2 badge is the only
              // label left; the graphic (plus its own sparkle hint once
              // the key becomes actionable) does the rest.
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _StepBadge(2),
                    const SizedBox(width: 12),
                    Expanded(
                      child: KeyPairingTrigger(
                        enabled: !_ctrl.isRunning && _passwordCtrl.text.isNotEmpty,
                        onConfirm: _pair,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pair() async {
    final password = _passwordCtrl.text;
    if (password.isEmpty) return;
    final shredding = _shredKey.currentState?.shred();
    if (shredding != null) unawaited(shredding);
    await _ctrl.pairWithPassword(password);
  }

  void _continueToVaultSetup(BuildContext context) {
    final linkingCtrl = context.read<LinkingController>();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LinkingScreen()),
    );
    // Kicks off immediately rather than landing on another idle screen
    // with its own START button - user just finished one setup step,
    // don't make them find and tap a second one.
    linkingCtrl.startLinking();
  }
}

// ── Password workflow, as a glance not a paragraph ──────────────────────────
//
// 2026-08-16: replaces "Enter your desktop login password once, just to
// install this phone's key. The desktop login password is never stored -
// only used for this one connection." Three icons read left to right:
// type it -> it installs a key -> it's never kept.
class _PasswordWorkflowStrip extends StatelessWidget {
  const _PasswordWorkflowStrip();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _step(Icons.password_rounded, 'TYPE ONCE'),
        _arrow(),
        _step(Icons.vpn_key_rounded, 'INSTALLS KEY'),
        _arrow(),
        _step(Icons.block_rounded, 'NEVER STORED'),
      ],
    );
  }

  Widget _step(IconData icon, String label) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: kGreen, size: 26),
          const SizedBox(height: 6),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: kTextDim, fontSize: 9, letterSpacing: 1, height: 1.3)),
        ],
      ),
    );
  }

  Widget _arrow() => const Padding(
        padding: EdgeInsets.only(bottom: 20),
        child: Icon(Icons.arrow_forward_rounded, color: kTextDim, size: 16),
      );
}

// ── Step number, no sentence needed ─────────────────────────────────────────
//
// 2026-08-16: replaces a full instruction sentence per direct feedback
// ("text is too verbose, users prefer images... perhaps 1 of 2 left of
// password and 2 of 2 left of the images"). Just a plain numbered marker -
// the password field and the key/lock graphic explain themselves.
class _StepBadge extends StatelessWidget {
  final int number;
  const _StepBadge(this.number);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: kGreen, width: 1.4),
      ),
      child: Text('$number',
          style: const TextStyle(
              color: kGreen, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

// ── Big, unmissable pairing success ─────────────────────────────────────────
//
// 2026-08-09: the previous success state was a single small teal line
// ("Paired", 14px) easy to miss entirely when scanning a stressed,
// error-fatigued screen - the user reported overlooking it outright and
// being left not knowing what to do next. Full-screen, high-contrast,
// with one obvious next action.
class _PairedSuccessView extends StatelessWidget {
  final VoidCallback onContinue;
  const _PairedSuccessView({required this.onContinue});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle, color: kGreen, size: 88),
          const SizedBox(height: 24),
          const Text('Paired!',
              style: TextStyle(
                  color: kStar, fontSize: 28, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          const Text(
            'Your phone is now trusted by your desktop.',
            style: TextStyle(color: kTextMid, fontSize: 15, height: 1.6),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onContinue,
              style: ElevatedButton.styleFrom(
                backgroundColor: kGreen,
                foregroundColor: kVoid,
                padding: const EdgeInsets.symmetric(vertical: 20),
                shape: const RoundedRectangleBorder(),
              ),
              child: const Text('CONTINUE - SET UP VAULT',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
