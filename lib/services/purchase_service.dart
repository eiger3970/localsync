// services/purchase_service.dart
//
// 2026-08-21: StoreKit plumbing, scaffolded ahead of having anything
// real to sell against. No Apple Developer account is active right
// now (lapsed, renewal blocked on funds - see project memory), so
// none of these product IDs exist in App Store Connect yet and
// nothing here has been tested against a real purchase. This exists
// so the shape is ready the moment there's a funded account and real
// product IDs - not because IAP ships today.
//
// First real product, per the 2026-08-18 business-model decision:
// a one-time, non-consumable unlock for the visual conflict-picker
// (conflicts_screen.dart / conflict_picker_screen.dart). Free tier
// keeps full manual text-based conflict resolution - that already
// works today, nothing is held back by this. $10k-$100k "buy
// everything" ceiling idea from 2026-08-21 is a real open pricing
// question, not reflected here - one real product, one real price.

import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 2026-08-21: placeholder, matching the app's own still-placeholder
// bundle ID (com.example.localsync, deliberately deferred per
// project memory). Must become a real reverse-domain ID under
// whichever bundle ID setup happens, and must exactly match the
// product ID entered in App Store Connect - not guessable in advance.
const kConflictPickerUnlockId = 'com.example.localsync.conflict_picker_unlock';

const _kUnlockedProductIdsKey = 'db_unlocked_product_ids';

class PurchaseService {
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  Set<String> _unlockedProductIds = {};

  bool get hasUnlockedConflictPicker =>
      _unlockedProductIds.contains(kConflictPickerUnlockId);

  Future<void> init() async {
    _unlockedProductIds = await _loadUnlocked();
    // 2026-08-21: not started automatically from anywhere yet (no
    // caller wires this in) - starting an StoreKit purchase-stream
    // listener with no real product IDs behind it has nothing
    // meaningful to do, and would just be an untested code path
    // sitting live in the app for no reason. Call explicitly once
    // there's a real reason to.
    _subscription = _iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onDone: () => _subscription?.cancel(),
      onError: (_) {},
    );
  }

  void dispose() => _subscription?.cancel();

  Future<bool> get isAvailable => _iap.isAvailable();

  Future<ProductDetailsResponse> queryProducts(Set<String> ids) =>
      _iap.queryProductDetails(ids);

  Future<void> buy(ProductDetails product) async {
    final param = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  Future<void> restorePurchases() => _iap.restorePurchases();

  Future<void> _handlePurchaseUpdates(
      List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        _unlockedProductIds.add(purchase.productID);
        await _saveUnlocked(_unlockedProductIds);
      }
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  Future<Set<String>> _loadUnlocked() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_kUnlockedProductIdsKey) ?? []).toSet();
  }

  Future<void> _saveUnlocked(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kUnlockedProductIdsKey, ids.toList());
  }
}
