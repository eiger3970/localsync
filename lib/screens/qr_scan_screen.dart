// screens/qr_scan_screen.dart
//
// 2026-09-04: Settings field 3/4's own QR scan button - real gap found,
// live: the desktop's git bare repo path is long enough to wrap across
// multiple lines on screen, and iOS Live Text/OCR bakes in a line break
// at the wrap point when copied via the system Camera app - the
// Settings field then silently rejects the paste (embedded newline
// mid-path). A user-generated QR code already confirmed to work end to
// end (one atomic string, no wrap point to misinterpret) - this scans
// one in-app instead of the clipboard/app-switch round trip through the
// system Camera app. Pops the decoded string straight back to whichever
// Settings field opened it.

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../theme.dart';

class QrScanScreen extends StatefulWidget {
  // 2026-09-04: shown in the app bar so a user scanning field 4 right
  // after field 3 isn't left guessing which field the result will land
  // in - real risk given both fields' scan buttons open this same
  // screen.
  final String fieldLabel;

  const QrScanScreen({super.key, required this.fieldLabel});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _controller = MobileScannerController();
  // 2026-09-04: onDetect can fire multiple times for the same code
  // while the camera keeps streaming frames - without this, a slow
  // Navigator.pop could let a second detection queue a second pop and
  // crash on an already-unmounted route.
  bool _handled = false;

  // 2026-09-22: real feedback, live - "I'm just an ignorant user, the
  // app... needs to manage this." A real user scanned the website's
  // own desktop-install QR code (a `sudo apt install ...` terminal
  // command, meant for the DESKTOP, nothing to do with this screen)
  // with THIS scanner instead of a real user-generated path QR code -
  // there's no visual difference between "a QR code meant for this
  // field" and "a QR code meant for something else entirely," so
  // blindly accepting whatever text a camera decodes and stuffing it
  // into a Settings path field was always going to happen to someone.
  // Rejects anything that looks like a shell command or a URL instead
  // of silently corrupting the field - simple pattern check, not
  // perfect path validation (a real path can contain almost anything),
  // but catches exactly this real failure mode and anything shaped
  // like it.
  static final _obviouslyNotAPathPattern = RegExp(
      r'^(sudo|curl|wget|bash|sh|apt|apt-get|https?://)\b|\$\(|&&|\|\|');

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final value = capture.barcodes.isNotEmpty
        ? capture.barcodes.first.rawValue
        : null;
    if (value == null || value.isEmpty) return;
    if (_obviouslyNotAPathPattern.hasMatch(value.trim())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "That QR code isn't a path - it looks like a terminal "
              'command or a link. Scan the one meant for this field '
              'instead.',
              style: TextStyle(fontSize: 14)),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    _handled = true;
    Navigator.pop(context, value);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kVoid,
      appBar: AppBar(
        backgroundColor: kVoid,
        title: Text('Scan ${widget.fieldLabel}',
            style: TextStyle(color: kStar, fontSize: 17)),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
              color: kVoid.withValues(alpha: 0.85),
              child: Text(
                'Point your camera at the QR code shown on your desktop.',
                textAlign: TextAlign.center,
                style: TextStyle(color: kTextMid, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
