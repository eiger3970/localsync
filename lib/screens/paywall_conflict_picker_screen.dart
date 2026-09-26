// screens/paywall_conflict_picker_screen.dart
//
// 2026-09-26: Ken - "users can fix most conflicts manually, but as
// problems grow, they can buy convenience." The Visual picker (see both
// versions side by side, tap to keep one) was free for everyone, so its
// US$14.99 purchase unlocked nothing. Viewing the comparison stays free
// (it doubles as the preview of what's being bought); keeping a side
// with one tap is what this unlocks. Same layout as
// paywall_keep_both_cleanup_screen.dart, one-time purchase.
import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../services/purchase_service.dart';
import '../theme.dart';

class PaywallConflictPickerScreen extends StatefulWidget {
  final PurchaseService purchases;
  const PaywallConflictPickerScreen({super.key, required this.purchases});

  @override
  State<PaywallConflictPickerScreen> createState() =>
      _PaywallConflictPickerScreenState();
}

class _PaywallConflictPickerScreenState
    extends State<PaywallConflictPickerScreen> {
  bool _busy = false;
  bool _checked = false;
  String? _error;
  Package? _package;
  String? _priceLabel;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final offerings = await widget.purchases.getOfferings();
    final package = offerings?.current?.availablePackages
        .where((p) =>
            p.storeProduct.identifier.contains(kConflictPickerEntitlementId))
        .firstOrNull;
    if (!mounted) return;
    setState(() {
      _package = package;
      _priceLabel = package?.storeProduct.priceString;
      _checked = true;
    });
  }

  Future<void> _buy() async {
    final package = _package;
    if (package == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final info = await widget.purchases.purchasePackage(package);
      final unlocked =
          info?.entitlements.active.containsKey(kConflictPickerEntitlementId) ??
              false;
      if (!mounted) return;
      if (unlocked) {
        Navigator.pop(context, true);
      } else {
        setState(() => _error = 'Purchase did not complete - try again.');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Purchase cancelled or failed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    final info = await widget.purchases.restorePurchases();
    if (!mounted) return;
    setState(() => _busy = false);
    final restored =
        info?.entitlements.active.containsKey(kConflictPickerEntitlementId) ??
            false;
    if (restored) {
      Navigator.pop(context, true);
    } else {
      setState(() => _error = 'Nothing to restore on this account.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kVoid,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  onPressed: () => Navigator.pop(context, false),
                  icon: Icon(Icons.close, color: kTextDim),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Container(
                  width: 90,
                  height: 90,
                  decoration:
                      BoxDecoration(color: kSurface, shape: BoxShape.circle),
                  child: Icon(Icons.compare_arrows, color: kGreen, size: 44),
                ),
              ),
              const SizedBox(height: 16),
              // 2026-09-18: real ask, live - "Keep both and clean up
              // (update text with your Title Case)." Sentence case
              // per house naming rule - was Title Case throughout this
              // screen (see the button and Restore purchase link
              // below too).
              Text('Visual picker',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 24, color: kStar)),
              const SizedBox(height: 8),
              Text(
                'Fixing a conflict by hand stays free, always. This adds '
                'one-tap convenience for when conflicts pile up.',
                textAlign: TextAlign.center,
                style: TextStyle(color: kTextMid, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 20),
              const _Bullet(
                  text: 'See both versions side by side, changes highlighted'),
              const _Bullet(text: 'Tap the one to keep - done'),
              const _Bullet(text: 'Everything backed up first, as always'),
              const _Bullet(text: 'Pay once. No subscription, ever.'),
              const Spacer(),
              if (_busy)
                Center(
                    child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: CircularProgressIndicator(color: kGreen),
                ))
              else if (_package != null)
                GestureDetector(
                  onTap: _buy,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: kGreen,
                      boxShadow: [
                        BoxShadow(
                            color: kGreen.withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Text('Unlock Visual picker - $_priceLabel',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w700,
                            fontSize: 16)),
                  ),
                )
              else if (_checked) ...[
                // No real product configured yet (no funded Apple
                // Developer account/RevenueCat product) - same honest
                // fallback as paywall_obsidian_screen.dart.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: kSurface, border: Border.all(color: kBorder)),
                  child: Text('Coming soon',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: kTextMid, fontStyle: FontStyle.italic)),
                ),
                // TEMPORARY - same reasoning as
                // paywall_obsidian_screen.dart's matching button: no
                // real purchase to make yet, so real device testing of
                // this feature would otherwise be completely blocked.
                // Must come out before a real App Store product/launch.
                // 2026-09-26: store builds (TestFlight/App Store) never show this -
                // strangers could unlock for free while products fail to load.
                // Sideloaded dev builds (no STORE_BUILD) keep it for testing.
                if (!kIsStoreBuild) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => Navigator.pop(context, true),
                    // 2026-09-18: real feedback, live - "Text under
                    // Coming soon too small." 11px -> 13px.
                    child: Text('Skip for testing (no product configured yet)',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: kTextDim,
                            fontSize: 13,
                            decoration: TextDecoration.underline)),
                  ),
                ],
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ],
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: _busy ? null : _restore,
                    child: Text('Restore purchase',
                        style: TextStyle(fontSize: 11, color: kTextDim)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet({required this.text});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(color: kSurface, shape: BoxShape.circle),
            child: Icon(Icons.check, color: kGreen, size: 14),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 14, color: kTextMid)),
          ),
        ],
      ),
    );
  }
}
