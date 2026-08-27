// services/purchase_service.dart
//
// 2026-08-21: switched from raw in_app_purchase (hand-rolled StoreKit
// calls) to RevenueCat's own SDK - see pubspec.yaml's comment for why.
// Still no funded Apple Developer account (see project memory), so
// even with a real RevenueCat key below, there's no actual App Store
// product to sell yet - init() succeeds and the SDK connects, but
// getOfferings() will come back empty until products exist on both
// sides. Never a secret worth protecting hard either way - RevenueCat
// public SDK keys are meant to ship inside client apps, same category
// as a Stripe publishable key.
//
// First real product, per the 2026-08-18 business-model decision:
// a one-time unlock for the visual word-diff conflict picker
// (conflicts_screen.dart / conflict_picker_screen.dart). Free tier
// keeps full manual text-based conflict resolution - that already
// works today, nothing is held back by this.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:purchases_flutter/purchases_flutter.dart';

// 2026-08-26: confirmed with the user directly - this IS the real key
// from an already-existing RevenueCat project, not a placeholder still
// waiting to be filled in (the TODO this replaced said otherwise and
// was stale). Never a secret worth protecting hard either way -
// RevenueCat's public SDK keys are meant to ship inside client apps,
// same as Stripe's publishable keys. What's still actually missing is
// the Apple Developer account / App Store product on the other side -
// see this file's header comment.
const kRevenueCatApiKey = 'test_hDQwOekjEiXiazeDDHAgGtqcCHx';

// RevenueCat entitlement identifier, configured in the RevenueCat
// dashboard once the project exists - not an App Store product ID
// directly (RevenueCat's own abstraction layer sits between the two).
const kConflictPickerEntitlementId = 'conflict_picker';

class PurchaseService {
  bool _configured = false;
  bool get isConfigured => _configured;

  Future<void> init() async {
    if (kRevenueCatApiKey.isEmpty) return;
    // purchases_flutter only has iOS/Android platform implementations -
    // calling configure() anywhere else throws MissingPluginException
    // and crashes app startup (hit running the desktop preview build).
    if (kIsWeb || !(Platform.isIOS || Platform.isAndroid)) return;
    await Purchases.configure(PurchasesConfiguration(kRevenueCatApiKey));
    _configured = true;
  }

  Future<bool> hasEntitlement(String id) async {
    if (!_configured) return false;
    try {
      final info = await Purchases.getCustomerInfo();
      return info.entitlements.active.containsKey(id);
    } catch (_) {
      return false;
    }
  }

  Future<Offerings?> getOfferings() async {
    if (!_configured) return null;
    try {
      return await Purchases.getOfferings();
    } catch (_) {
      return null;
    }
  }

  Future<CustomerInfo?> purchasePackage(Package package) async {
    if (!_configured) return null;
    return Purchases.purchasePackage(package);
  }

  Future<CustomerInfo?> restorePurchases() async {
    if (!_configured) return null;
    return Purchases.restorePurchases();
  }
}
