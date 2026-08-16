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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Connect to ${widget.desktopUser}@${widget.desktopIp}',
              style: const TextStyle(
                  color: kStar, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            const Text(
              'Enter your desktop login password once, just to install '
              'this phone\'s key. It is never stored - only used for this '
              'one connection.',
              style: TextStyle(color: kTextMid, fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 24),
            ShreddingPasswordField(
              key: _shredKey,
              controller: _passwordCtrl,
              enabled: !_ctrl.isRunning,
            ),
            const SizedBox(height: 8),
            // 2026-08-16: moved here (right under the field it explains)
            // after direct feedback that the old hint text sat below the
            // ~190px key/lock graphic instead of near the password field -
            // "unsure why TYPE THE PASSWORD FIRST is under the images
            // rather than directly under the Desktop password field".
            Text(
              _passwordCtrl.text.isEmpty
                  ? 'Type your password, then drag the key into the lock below to pair.'
                  : 'Drag the key into the lock to pair.',
              style: const TextStyle(color: kTextDim, fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 16),
            KeyPairingTrigger(
              enabled: !_ctrl.isRunning && _passwordCtrl.text.isNotEmpty,
              onConfirm: _pair,
            ),
            if (result is StepFailure) ...[
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: kSurface,
                  border: const Border(
                      left: BorderSide(color: Colors.redAccent, width: 2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(result.diagnosis,
                        style: const TextStyle(color: kStar, fontSize: 16)),
                    const SizedBox(height: 8),
                    Text(result.resolution,
                        style: const TextStyle(color: kTextDim, fontSize: 14, height: 1.6)),
                    if (result.debugDetail != null) ...[
                      const SizedBox(height: 12),
                      Text('Raw error (temporary diagnostic):',
                          style: const TextStyle(color: kTextDim, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(result.debugDetail!,
                          style: const TextStyle(
                              color: Colors.redAccent, fontSize: 13)),
                    ],
                  ],
                ),
              ),
            ],
          ],
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
