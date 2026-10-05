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
import '../theme.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../services/purchase_service.dart';
import '../widgets/paywall_cards.dart';
import 'welcome_hero_screen.dart' show wInk, wInkDim, wCream;

const _pBg1 = Color(0xFFF3FBFA);
const _pBg2 = Color(0xFFF1ECFA);
const _pVioletDark = kObsidianPurple;
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
        .where((p) => p.storeProduct.identifier.contains(kPkmSyncEntitlementId))
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
          info?.entitlements.active.containsKey(kPkmSyncEntitlementId) ?? false;
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
                // 2026-09-29: user - 3 swipeable picture cards (Notes,
                // Conflicts, Backups) instead of an icon + 4 bullets; the
                // price button below stays visible on every card.
                Expanded(
                  child: PaywallCards(
                      accent: _pVioletDark, ink: wInk, inkDim: wInkDim),
                ),
                const SizedBox(height: 12),
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
                      child: Text('Unlock Obsidian sync - $_priceLabel',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16)),
                    ),
                  )
                else if (_checked) ...[
                  // No real product configured yet (no funded Apple
                  // Developer account/RevenueCat product) - a quiet,
                  // honest state instead of a fake price on a dead
                  // button, same convention as pkm_sync_upsell.dart.
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: wCream, border: Border.all(color: _pVioletBg)),
                    child: Text('Coming soon',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: wInkDim, fontStyle: FontStyle.italic)),
                  ),
                  // 2026-09-02: real feedback, live - "I can't get past
                  // the paywall to setup my obsidian... make the
                  // paywall allow me through for the setup testing."
                  // There's genuinely no purchase to make yet (see
                  // above), so real device testing of the actual
                  // Obsidian vault-linking flow is otherwise completely
                  // blocked. TEMPORARY - labeled honestly, visible only
                  // in this already-"no product configured" state (so
                  // it can never appear alongside a real, purchasable
                  // price), and does exactly what a real purchase would
                  // do: pop(true). Must come out before a real App
                  // Store product/launch - remove this whole button
                  // once kPkmSyncEntitlementId has a real, purchasable
                  // RevenueCat product and this branch can go back to
                  // being a dead end.
                  // 2026-09-26: store builds (TestFlight/App Store) never show this -
                  // strangers could unlock for free while products fail to load.
                  // Sideloaded dev builds (no STORE_BUILD) keep it for testing.
                  if (!kIsStoreBuild) ...[
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => Navigator.pop(context, true),
                      // 2026-09-18: real feedback, live - "Text under
                      // Coming soon too small." 11px -> 13px, matching
                      // the sibling Keep Both & Clean Up screen's fix.
                      child: Text(
                          'Skip for testing (no product configured yet)',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: wInkDim,
                              fontSize: 13,
                              decoration: TextDecoration.underline)),
                    ),
                  ],
                ],
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
                      child: Text('Restore purchase',
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
