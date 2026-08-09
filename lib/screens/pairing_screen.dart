// screens/pairing_screen.dart
//
// One-time pairing: enter the desktop's login password to install this
// phone's SSH key. Password is never stored - only held in this screen's
// local state for the duration of the request.

import 'package:flutter/material.dart';
import '../theme.dart';
import '../features/linking/linking_state.dart';
import '../features/pairing/pairing_controller.dart';

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
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _ctrl = PairingController(
      desktopUser: widget.desktopUser,
      desktopIp:   widget.desktopIp,
    );
    _ctrl.addListener(_onChange);
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
            TextField(
              controller: _passwordCtrl,
              obscureText: _obscure,
              enabled: !_ctrl.isRunning,
              style: const TextStyle(color: kStar),
              decoration: InputDecoration(
                labelText: 'Desktop password',
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onSubmitted: (_) => _pair(),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _ctrl.isRunning ? null : _pair,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kTeal,
                  foregroundColor: kVoid,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: const RoundedRectangleBorder(),
                ),
                child: Text(_ctrl.isRunning ? 'PAIRING…' : 'PAIR'),
              ),
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
                        style: const TextStyle(color: kStar, fontSize: 13)),
                    const SizedBox(height: 8),
                    Text(result.resolution,
                        style: const TextStyle(color: kTextDim, fontSize: 12, height: 1.6)),
                    if (result.debugDetail != null) ...[
                      const SizedBox(height: 12),
                      Text('Raw error (temporary diagnostic):',
                          style: const TextStyle(color: kTextDim, fontSize: 11)),
                      const SizedBox(height: 4),
                      Text(result.debugDetail!,
                          style: const TextStyle(
                              color: Colors.redAccent, fontSize: 11)),
                    ],
                  ],
                ),
              ),
            ],
            if (result is StepSuccess) ...[
              const SizedBox(height: 20),
              Row(
                children: const [
                  Icon(Icons.check_circle_outline, color: kTeal, size: 20),
                  SizedBox(width: 8),
                  Text('Paired', style: TextStyle(color: kTeal, fontSize: 14)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pair() async {
    if (_passwordCtrl.text.isEmpty) return;
    await _ctrl.pairWithPassword(_passwordCtrl.text);
    _passwordCtrl.clear();
  }
}
