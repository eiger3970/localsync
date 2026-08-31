// screens/paywall_obsidian_screen.dart
//
// 2026-08-31: full-screen paywall for the Obsidian/PKM unlock
// (kPkmSyncEntitlementId), adapted from a proven mobile-paywall
// reference (icon, clear headline, concrete benefit bullets, one price,
// one CTA, legal footer) - kept the structure, dropped the
// subscription/free-trial mechanic the reference used, since this is a
// real one-time purchase (purchase_service.dart), not a subscription,
// and Apple's native trial support is subscription-only anyway. Same
// honest "Coming soon" fallback as pkm_sync_upsell.dart when no real
// RevenueCat product exists yet - never a fake price on a dead button.
//
// Only ONE price option, matching what's actually configured today
// (kPkmSyncEntitlementId). The design draft explored a second
// "Everything Bundle" option, but no such product/entitlement exists
// yet - adding it here would be exactly the kind of fake-looking,
// can-never-be-pressed UI this codebase's other IAP surfaces
// deliberately avoid. Add it for real once that product exists.

import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../services/purchase_service.dart';
import 'welcome_hero_screen.dart' show wInk, wInkDim, wCream;

const _pBg1 = Color(0xFFF3FBFA);
const _pBg2 = Color(0xFFF1ECFA);
const _pVioletDark = Color(0xFF6B4FA0);
const _pVioletBg = Color(0xFFF1ECFA);

class PaywallObsidianScreen extends StatefulWidget {
  final PurchaseService purchases;
  const PaywallObsidianScreen({super.key, required this.purchases});

  @override
  State<PaywallObsidianScreen> createState() => _PaywallObsidianScreenState();
}

class _PaywallObsidianScreenState extends State<PaywallObsidianScreen> {
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
            p.storeProduct.identifier.contains(kPkmSyncEntitlementId))
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
          info?.entitlements.active.containsKey(kPkmSyncEntitlementId) ??
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
        info?.entitlements.active.containsKey(kPkmSyncEntitlementId) ?? false;
    if (restored) {
      Navigator.pop(context, true);
    } else {
      setState(() => _error = 'Nothing to restore on this account.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_pBg1, _pBg2],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    onPressed: () => Navigator.pop(context, false),
                    icon: Icon(Icons.close, color: wInkDim),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: const BoxDecoration(
                        color: _pVioletBg, shape: BoxShape.circle),
                    child: Icon(Icons.auto_stories_rounded,
                        color: _pVioletDark, size: 44),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Unlock Obsidian Sync',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 24,
                        color: wInk)),
                const SizedBox(height: 20),
                const _Bullet(text: 'Full Obsidian vault sync'),
                const _Bullet(
                    text: 'Visual conflict picker — see both, tap to choose'),
                const _Bullet(
                    text: 'Real conflict protection — never lose a note'),
                const _Bullet(text: 'Pay once. No subscription, ever.'),
                const Spacer(),
                if (_busy)
                  const Center(
                      child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(color: _pVioletDark),
                  ))
                else if (_package != null)
                  GestureDetector(
                    onTap: _buy,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _pVioletDark,
                        boxShadow: [
                          BoxShadow(
                              color: _pVioletDark.withValues(alpha: 0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4)),
                        ],
                      ),
                      child: Text('Unlock Obsidian Sync — $_priceLabel',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16)),
                    ),
                  )
                else if (_checked)
                  // No real product configured yet (no funded Apple
                  // Developer account/RevenueCat product) - a quiet,
                  // honest state instead of a fake price on a dead
                  // button, same convention as pkm_sync_upsell.dart.
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: wCream,
                        border: Border.all(color: _pVioletBg)),
                    child: Text('Coming soon',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: wInkDim, fontStyle: FontStyle.italic)),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 12)),
                ],
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: _busy ? null : _restore,
                      child: Text('Restore Purchase',
                          style: TextStyle(fontSize: 11, color: wInkDim)),
                    ),
                  ],
                ),
              ],
            ),
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
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
                color: _pVioletBg, shape: BoxShape.circle),
            child: Icon(Icons.check, color: _pVioletDark, size: 14),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 14, color: wInk)),
          ),
        ],
      ),
    );
  }
}
