// widgets/conflict_picker_upsell.dart
//
// 2026-08-21: the real first IAP product, per the 2026-08-18 business-
// model decision - a one-time unlock for the visual word-diff
// conflict picker. NOT wired into conflicts_screen.dart or
// conflict_picker_screen.dart yet, and deliberately so: those screens
// are exactly what's being real-device tested right now, and there is
// no funded Apple Developer account / no RevenueCat project set up
// yet (see purchase_service.dart's header). Gating the already-working
// feature behind an unpurchasable button would break testing for no
// reason. This widget is a complete, ready piece - wiring it into the
// real screens is a deliberate later step, not forgotten.
//
// Rewritten same day, switched to RevenueCat (purchases_flutter)
// instead of raw in_app_purchase - see purchase_service.dart.
//
// Spec, user's own words (2026-08-18): "a small, always-visible
// 'visual fix' button/nag... framed like McDonald's 'would you like
// fries with that?' - a genuine lift/convenience offer, fair price,
// NOT naggy/annoying." Free tier (manual, raw-text resolution) stays
// fully functional regardless - this is an upsell at the point of
// pain, not a lock screen.

import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../theme.dart';
import '../services/purchase_service.dart';

class ConflictPickerUpsell extends StatefulWidget {
  final PurchaseService purchases;
  const ConflictPickerUpsell({super.key, required this.purchases});

  @override
  State<ConflictPickerUpsell> createState() => _ConflictPickerUpsellState();
}

class _ConflictPickerUpsellState extends State<ConflictPickerUpsell> {
  bool _busy = false;
  Package? _package;
  String? _priceLabel;

  @override
  void initState() {
    super.initState();
    _loadOffering();
  }

  Future<void> _loadOffering() async {
    final offerings = await widget.purchases.getOfferings();
    final package = offerings?.current?.availablePackages
        .where((p) => p.storeProduct.identifier
            .contains(kConflictPickerEntitlementId))
        .firstOrNull;
    if (!mounted || package == null) return;
    setState(() {
      _package = package;
      _priceLabel = package.storeProduct.priceString;
    });
  }

  Future<void> _buy() async {
    final package = _package;
    if (package == null) return;
    setState(() => _busy = true);
    try {
      await widget.purchases.purchasePackage(package);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Same fair-value framing every time this shows - never louder or
    // more urgent than the free path sitting right next to it.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurface,
        border: Border.all(color: kBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_fix_high, color: kGreen, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('See both versions side by side, tap to keep',
                    style: TextStyle(
                        color: kStar, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  'Optional - manual resolution in Obsidian already works',
                  style: TextStyle(color: kTextMid, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _busy
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: kGreen),
                )
              : OutlinedButton(
                  onPressed: _package == null ? null : _buy,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: kGreen),
                    foregroundColor: kGreen,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                  child: Text(_priceLabel ?? r'$19.99',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                ),
        ],
      ),
    );
  }
}
