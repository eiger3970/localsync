// 2026-08-23: real feature request, live - "make the circle a shield
// hinting at encryption... make it tappable to open a workflow process
// on educating the user on how local transmission works cybersecurity."
// Deliberately native Flutter widgets (boxes + connecting lines), not a
// real .svg asset - this app has a real history of SVG assets breaking
// invisibly with no way to preview before a sideload (see the pairing
// screen's SVG saga). Same visual effect (a step-by-step workflow),
// zero new asset dependency, zero new render risk.
import 'package:flutter/material.dart';
import '../theme.dart';

class SecurityInfoScreen extends StatelessWidget {
  const SecurityInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kVoid,
        title: Text('How your data is protected',
            style: TextStyle(color: kStar)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 2026-08-23: was emoji here ("text emoji is only 7 bytes...
            // use emojis unless they look terrible, then svg design").
            // 2026-09-17: real feedback, live - "change all four emojis
            // to svg images." Material icons instead of hand-drawn .svg
            // assets specifically - same reuse of vocabulary
            // PasswordInfoRow already uses elsewhere in the app
            // (vpn_key_outlined, lock_outline), zero new asset-loading
            // risk (see this file's own SVG-breakage note above).
            const _Step(
              icon: Icons.vpn_key_outlined,
              title: 'Your phone holds its own key',
              body:
                  'An ed25519 key pair is generated on this device during '
                  'pairing. The private half never leaves your phone.',
            ),
            const _Arrow(),
            const _Step(
              icon: Icons.lock_outline,
              title: 'Every connection is SSH',
              body:
                  'Phone and desktop only ever talk over SSH - the same '
                  'protocol financial institutions and governments use for secure remote '
                  'access, not a custom or homemade scheme.',
            ),
            const _Arrow(),
            const _Step(
              icon: Icons.shield_outlined,
              title: 'Encrypted the whole way',
              body:
                  'SSH negotiates the connection with ECDH key exchange, '
                  'then encrypts everything sent with AES-256 or '
                  'ChaCha20-Poly1305 - both standard, publicly audited '
                  'ciphers, not proprietary encryption.',
            ),
            const _Arrow(),
            const _Step(
              icon: Icons.cloud_off_outlined,
              title: 'No cloud, ever',
              body:
                  'Your notes travel directly between your own two '
                  'devices over your own network. Nothing passes through '
                  'a server we run or anyone else\'s.',
            ),
            const SizedBox(height: 24),
            Text(
              'This is the same real cryptography your financial '
              'institution\'s app uses - not marketing language.',
              style: TextStyle(color: kTextMid, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _Step({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: kVoid,
            border: Border.all(color: kGreen, width: 1.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(child: Icon(icon, color: kGreen, size: 22)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: kStar, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(body, style: TextStyle(color: kTextMid, fontSize: 14)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SizedBox(
        width: 44,
        child: Center(
          child: Icon(Icons.arrow_downward, color: kTextDim, size: 18),
        ),
      ),
    );
  }
}
