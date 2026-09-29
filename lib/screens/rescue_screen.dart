// screens/rescue_screen.dart
//
// 2026-09-29: Ken - Rescue Package: "one big red button, users can just
// hit for an emergency ... one payment, one button, one tap." "Button image
// to be shiny and welcoming for a smash ... with a slow red glow on it, so
// users know it's live and active." The word on the button is live text
// (not part of the picture) so it can be translated with the app.
// Tap: pays (skipped once owned), then runRescue does everything by itself.
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/purchase_service.dart';
import '../services/repository_provider.dart';
import '../services/rescue_service.dart';
import '../theme.dart';

const _red = Color(0xFFFF2D3D);

enum _Stage { ready, paying, rescuing, done }

class RescueScreen extends StatefulWidget {
  const RescueScreen({super.key});

  @override
  State<RescueScreen> createState() => _RescueScreenState();
}

class _RescueScreenState extends State<RescueScreen>
    with TickerProviderStateMixin {
  late final AnimationController _glow = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2800))
    ..repeat(reverse: true);
  // 2026-09-29: Ken - the shine "can have a blurry face or body silhouette
  // that when the phone moves, the reflection would move like a real
  // camera." The shine slides with the phone's tilt, like a reflection.
  StreamSubscription<AccelerometerEvent>? _tiltSub;
  Offset _tilt = Offset.zero; // -1..1, smoothed
  late final AnimationController _files = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400));
  _Stage _stage = _Stage.ready;
  bool _owned = false;
  Package? _package;
  String? _price;
  String? _error;
  String _step = '';
  RescueResult? _result;

  @override
  void initState() {
    super.initState();
    _load();
    try {
      _tiltSub = accelerometerEventStream(
              samplingPeriod: SensorInterval.uiInterval)
          .listen((e) {
        final target = Offset((-e.x / 6).clamp(-1.0, 1.0),
            ((e.y - 6) / 6).clamp(-1.0, 1.0));
        if (mounted) setState(() => _tilt = _tilt * 0.85 + target * 0.15);
      }, onError: (_) {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _tiltSub?.cancel();
    _files.dispose();
    _glow.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final purchases = context.read<PurchaseService>();
    final owned = await purchases.hasEntitlement(kRescueEntitlementId);
    final offerings = await purchases.getOfferings();
    final package = offerings?.current?.availablePackages
        .where((p) => p.storeProduct.identifier == kRescueProductId)
        .firstOrNull;
    if (!mounted) return;
    setState(() {
      _owned = owned;
      _package = package;
      _price = package?.storeProduct.priceString;
    });
  }

  Future<void> _smash() async {
    if (_stage != _Stage.ready) return;
    final purchases = context.read<PurchaseService>();
    final provider = context.read<RepositoryProvider>();
    // 2026-09-29: Ken - "I tap is instant, set off the fire brigade, make
    // it crystal clear ... first the user needs an immediate confirmation
    // with the visuals, then do whatever background stuff." The screen
    // changes on the tap itself, then the work starts.
    setState(() {
      _error = null;
      _stage = _owned ? _Stage.rescuing : _Stage.paying;
      _step = _owned ? 'Starting the rescue' : '';
    });
    _files.repeat();
    await WidgetsBinding.instance.endOfFrame;
    if (!_owned) {
      final package = _package;
      // Sideloaded test builds (no STORE_BUILD) have no real product to buy -
      // same "skip for testing" rule as the other price screens. Store builds
      // never get here without paying.
      if (package == null && !kIsStoreBuild) {
        _owned = true;
      } else if (package == null) {
        _files.stop();
        setState(() {
          _stage = _Stage.ready;
          _error =
              'Rescue can\'t be bought right now - check your internet, then try again.';
        });
        return;
      }
    }
    if (!_owned) {
      final package = _package!;
      setState(() => _stage = _Stage.paying);
      try {
        final info = await purchases.purchasePackage(package);
        _owned = info?.entitlements.active.containsKey(kRescueEntitlementId) ??
            false;
      } catch (_) {
        _owned = false;
      }
      if (!mounted) return;
      if (!_owned) {
        _files.stop();
        setState(() {
          _stage = _Stage.ready;
          _error = 'Payment did not go through - nothing was charged. Try again.';
        });
        return;
      }
    }
    setState(() {
      _stage = _Stage.rescuing;
      _step = 'Starting the rescue';
    });
    if (!mounted) return;
    final result = await runRescue(provider,
        onStep: (s) => mounted ? setState(() => _step = s) : null);
    if (!mounted) return;
    _files.stop();
    setState(() {
      _result = result;
      _stage = _Stage.done;
    });
  }

  Future<void> _restorePurchase() async {
    final info = await context.read<PurchaseService>().restorePurchases();
    if (!mounted) return;
    final owned =
        info?.entitlements.active.containsKey(kRescueEntitlementId) ?? false;
    setState(() {
      _owned = owned;
      _error = owned ? null : 'No Rescue Package on this Apple account yet.';
    });
  }

  void _askUs() => launchUrl(
      Uri.parse('https://kworld.space/contact?help=1&msg='
          '${Uri.encodeComponent('LocalSync Rescue: ')}'),
      mode: LaunchMode.externalApplication);

  Widget _fact(String noun, String text, {Widget? trailing}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration:
            BoxDecoration(border: Border(top: BorderSide(color: kBorder))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.check_rounded, color: _red, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: noun,
                    style: TextStyle(color: kStar, fontWeight: FontWeight.w700)),
                TextSpan(text: ': $text'),
                if (trailing != null)
                  WidgetSpan(
                      alignment: PlaceholderAlignment.middle, child: trailing),
              ]),
              style: TextStyle(color: kTextMid, fontSize: 14, height: 1.35),
            ),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final busy = _stage == _Stage.paying || _stage == _Stage.rescuing;
    return Scaffold(
      backgroundColor: kVoid,
      appBar: AppBar(backgroundColor: kVoid, iconTheme: IconThemeData(color: kStar)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Rescue', style: TextStyle(color: _red)),
                TextSpan(text: ': one tap', style: TextStyle(color: kStar)),
              ]),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
                _stage == _Stage.done
                    ? 'Done. Your notes are back.'
                    : 'Notes lost or messed up?\nOne payment. One button. One tap.',
                textAlign: TextAlign.center,
                style: TextStyle(color: kTextMid, fontSize: 15, height: 1.4)),
            const SizedBox(height: 8),
            Center(
              child: GestureDetector(
                onTap: busy || _stage == _Stage.done ? null : _smash,
                child: AnimatedBuilder(
                  animation: _glow,
                  builder: (_, __) => SizedBox(
                    width: 280,
                    height: 280,
                    child: CustomPaint(
                      painter: RedButtonPainter(
                          glow: busy ? 1 : _glow.value, tilt: _tilt),
                      child: Center(
                        child: busy
                            ? const SizedBox(
                                width: 46,
                                height: 46,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 4))
                            : Text(
                                _stage == _Stage.done ? 'DONE' : 'RESCUE',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 31,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 2,
                                    shadows: [
                                      Shadow(
                                          color: Color(0xFFA0000F),
                                          blurRadius: 2,
                                          offset: Offset(0, 1)),
                                    ])),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_stage == _Stage.rescuing)
              SizedBox(
                  height: 70,
                  child: AnimatedBuilder(
                      animation: _files,
                      builder: (_, __) =>
                          CustomPaint(painter: _FilesHomePainter(_files.value)))),
            const SizedBox(height: 4),
            Text(
              switch (_stage) {
                _Stage.paying => 'Opening payment...',
                _Stage.rescuing => _step.isEmpty ? 'Rescuing...' : '$_step...',
                _Stage.done => _summary(),
                _Stage.ready => _owned
                    ? 'Owned - tap any time, LocalSync does the rest'
                    : _package == null && !kIsStoreBuild
                    ? 'Test build - no payment, LocalSync does the rest'
                    : '${_price ?? ''}${_price == null ? '' : ' - '}LocalSync does the rest',
              },
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: kStar, fontSize: 15, fontWeight: FontWeight.w600),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _red, fontSize: 13)),
            ],
            const SizedBox(height: 18),
            _fact('Backups', 'best saved copy put back automatically'),
            _fact('Conflicts', 'every one kept and cleaned up'),
            _fact('Help', 'a real person, if you want one - ',
                trailing: GestureDetector(
                  onTap: _askUs,
                  child: const Text('Ask us',
                      style: TextStyle(
                          color: _red,
                          fontSize: 14,
                          decoration: TextDecoration.underline)),
                )),
            _fact('Lost notes', 'all brought back, even ones removed by mistake'),
            _fact('You', 'nothing else to do'),
            if (!_owned && _stage == _Stage.ready) ...[
              const SizedBox(height: 14),
              Center(
                child: TextButton(
                  onPressed: _restorePurchase,
                  child: Text('Restore purchase',
                      style: TextStyle(color: kTextDim, fontSize: 13)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _summary() {
    final r = _result!;
    if (!r.anythingDone && r.problems.isEmpty) {
      return 'Nothing was missing or in conflict - your notes are fine.';
    }
    final parts = [
      if (r.notesBack > 0) '${r.notesBack} note${r.notesBack == 1 ? '' : 's'} back',
      if (r.conflictsFixed > 0)
        '${r.conflictsFixed} conflict${r.conflictsFixed == 1 ? '' : 's'} cleaned up',
    ];
    final done = parts.isEmpty ? '' : '${parts.join(', ')}, sent to your desktop.';
    return r.problems.isEmpty
        ? done
        : '$done ${r.problems.length} folder${r.problems.length == 1 ? '' : 's'} could not be rescued - tap Ask us.';
  }
}

/// Glossy red crystal button with a slow red glow, no rim.
class RedButtonPainter extends CustomPainter {
  final double glow; // 0..1, slow pulse
  final Offset tilt; // -1..1, phone tilt - moves the reflection
  RedButtonPainter({required this.glow, this.tilt = Offset.zero});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2 - 3);
    final r = size.width * 0.368;
    // Glow: starts at the button's edge and fades out - a soft halo, not
    // a ring. Brightens and widens slowly with [glow].
    // 2026-09-29: Ken - "a larger glow would make a live button".
    final glowR = size.width / 2 * (0.95 + 0.05 * glow);
    canvas.drawCircle(
        c,
        glowR,
        Paint()
          ..shader = RadialGradient(colors: [
            _red.withValues(alpha: 0.45 + 0.50 * glow),
            _red.withValues(alpha: 0.18 + 0.27 * glow),
            _red.withValues(alpha: 0),
          ], stops: [r / glowR * 0.98, (r / glowR + 1) / 2, 1]).createShader(
              Rect.fromCircle(center: c, radius: glowR)));
    final dome = Rect.fromCircle(center: c, radius: r);
    // Dome
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(-0.2, -0.4),
            radius: 0.8,
            colors: [
              Color(0xFFFFB3B8),
              Color(0xFFFF4D5A),
              Color(0xFFE0001B),
              Color(0xFF8A000F),
            ],
            stops: [0, 0.25, 0.65, 1],
          ).createShader(dome));
    // Warm light from below
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(0, 0.7),
            radius: 0.6,
            colors: [
              const Color(0xFFFF7A82).withValues(alpha: 0.55),
              const Color(0xFFFF7A82).withValues(alpha: 0),
            ],
          ).createShader(dome));
    // Crystal facets
    canvas.save();
    canvas.clipPath(Path()..addOval(dome));
    final light = Paint()..color = Colors.white.withValues(alpha: 0.12);
    final dark = Paint()..color = Colors.black.withValues(alpha: 0.08);
    Offset p(double a, double k) =>
        c + Offset(math.cos(a) * r * k, math.sin(a) * r * k);
    for (var i = 0; i < 6; i++) {
      final a0 = -math.pi / 2 + i * math.pi / 3;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(p(a0, 1.05).dx, p(a0, 1.05).dy)
        ..lineTo(p(a0 + math.pi / 3, 1.05).dx, p(a0 + math.pi / 3, 1.05).dy)
        ..close();
      canvas.drawPath(path, i.isEven ? light : dark);
    }
    canvas.restore();
    // Shine
    // Reflection: moves opposite the tilt, like a real glossy surface, with
    // a soft darker shape in it (the viewer's head and shoulders).
    final sc = Offset(c.dx - r * 0.18 - tilt.dx * r * 0.22,
        c.dy - r * 0.56 - tilt.dy * r * 0.12);
    final shine = Rect.fromCenter(
        center: sc,
        width: r * 1.13,
        height: r * 0.57);
    canvas.drawOval(
        shine,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0.95),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(shine));
    final blur = Paint()
      ..color = const Color(0xFFB0001A).withValues(alpha: 0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawCircle(sc + Offset(0, -r * 0.04), r * 0.09, blur); // head
    canvas.drawOval(
        Rect.fromCenter(
            center: sc + Offset(0, r * 0.16), width: r * 0.42, height: r * 0.2),
        blur); // shoulders
    canvas.drawCircle(Offset(c.dx + r * 0.47, c.dy + r * 0.41), r * 0.065,
        Paint()..color = Colors.white.withValues(alpha: 0.35));
  }

  @override
  bool shouldRepaint(RedButtonPainter old) =>
      old.glow != glow || old.tilt != tilt;
}

/// 2026-09-29: Ken - "show an svg image of files being rescued." Three
/// notes fly in an arc from the left into a folder on the right, looping,
/// while Rescue works.
class _FilesHomePainter extends CustomPainter {
  final double t; // 0..1 loop
  _FilesHomePainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final folder = Offset(size.width / 2 + 70, size.height / 2 + 6);
    final start = Offset(size.width / 2 - 90, size.height / 2 + 8);
    final line = Paint()
      ..color = const Color(0xFFB9B5D3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final fill = Paint()..color = const Color(0xFF0D0B1A);
    // Folder
    final fr = Rect.fromCenter(center: folder, width: 44, height: 32);
    canvas.drawRRect(
        RRect.fromRectAndRadius(fr, const Radius.circular(4)),
        Paint()..color = _red.withValues(alpha: 0.9));
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(fr.left, fr.top - 5, 18, 8), const Radius.circular(2)),
        Paint()..color = _red.withValues(alpha: 0.9));
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1.0;
      final x = start.dx + (folder.dx - start.dx) * p;
      final y = start.dy - math.sin(p * math.pi) * 34 + (folder.dy - start.dy) * p;
      final scale = 1 - 0.35 * p;
      final opacity = p < 0.85 ? 1.0 : (1 - (p - 0.85) / 0.15);
      canvas.save();
      canvas.translate(x, y);
      canvas.scale(scale);
      final note = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: 20, height: 26),
          const Radius.circular(3));
      canvas.drawRRect(note, fill..color = fill.color.withValues(alpha: opacity));
      canvas.drawRRect(note, line..color = line.color.withValues(alpha: opacity));
      for (final dy in [-6.0, 0.0, 6.0]) {
        canvas.drawLine(Offset(-5, dy), Offset(5, dy), line);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_FilesHomePainter old) => old.t != t;
}
