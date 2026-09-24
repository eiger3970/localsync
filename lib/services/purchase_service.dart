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
const kRevenueCatTestApiKey = 'test_hDQwOekjEiXiazeDDHAgGtqcCHx';

// 2026-09-24: launch prep - "can the IAP stuff be done?" The test key
// above only talks to RevenueCat's Test Store (no real money, works in
// sideloaded builds). A real App Store purchase needs RevenueCat's
// public Apple key (starts "appl_") AND a signed App Store/TestFlight
// build - a sideloaded GitHub Actions build can't make real StoreKit
// purchases at all. So the real key is used only when the build says
// it's a store build:
//   flutter build ipa --release --dart-define=STORE_BUILD=true
// Every other build (GitHub Actions, local, tests) keeps the test key,
// exactly as before. Paste the key from RevenueCat -> Project settings
// -> API keys -> App Store; like the test key, it's public by design.
const kRevenueCatAppleApiKey = 'appl_SWulxOqLMjGGhkHALlxnHqAIDXP';
const kIsStoreBuild = bool.fromEnvironment('STORE_BUILD');

/// The key this build configures RevenueCat with. A store build with
/// no Apple key pasted yet throws here, so init() never configures
/// RevenueCat and every paywall shows its "not available" state -
/// visible on the first TestFlight run, instead of silently shipping
/// the Test Store to real customers.
String get kRevenueCatApiKey {
  if (!kIsStoreBuild) return kRevenueCatTestApiKey;
  if (kRevenueCatAppleApiKey.isEmpty) {
    throw StateError('STORE_BUILD=true but kRevenueCatAppleApiKey is empty '
        '- paste the appl_ key into purchase_service.dart first.');
  }
  return kRevenueCatAppleApiKey;
}

// RevenueCat entitlement identifier, configured in the RevenueCat
// dashboard once the project exists - not an App Store product ID
// directly (RevenueCat's own abstraction layer sits between the two).
const kConflictPickerEntitlementId = 'conflict_picker';

// 2026-08-27: Tier 1 (docs/product-tiers.md) - unlocks Obsidian/PKM
// awareness itself: vault linking, the full "special recipe" pairing
// sequence, Kanban-safe conflict merge. This is the actual free/paid
// boundary per the 2026-08-26 business-model redraw - kConflictPickerEntitlementId
// above is one tier ABOVE this one (the visual picker on top of PKM
// sync already being unlocked), not a substitute for it. Not yet
// configured as a real product in the RevenueCat dashboard - same
// "no funded Apple Developer account yet" blocker as the rest of this
// file's header comment.
const kPkmSyncEntitlementId = 'pkm_sync';

// 2026-09-08: Tier 3 addition (docs/product-tiers.md) - one-tap Undo
// for Keep Both (kept_both_screen.dart). User's own words: "this 1 tap
// is a IAP." Not yet wired to an actual purchase check anywhere - same
// "no funded Apple Developer account / no real RevenueCat product yet"
// blocker as kPkmSyncEntitlementId above. Registered here now so
// wiring it in later is a one-line change, not a naming decision too.
const kKeepBothUndoEntitlementId = 'keep_both_undo';

// 2026-09-16: Tier 3 addition (docs/product-tiers.md) - "Keep Both &
// Clean Up." Real feedback, live, on an actual conflict - "text with
// clock is out of order on both desktop and phone" after running the
// free KEEP BOTH, then "keeping both is a concatenate dump, the IAP
// KEEP BOTH and clean up, does the correct job for a paid IAP level."
// Free KEEP BOTH stays exactly as it always was (a plain concatenate,
// only reordered at the whole-body level - see conflict_repair.dart's
// journalOrderedBodies); this entitlement gates the paragraph-level
// chronological interleave (journalOrderedEntries) instead. Same "no
// funded Apple Developer account / no real RevenueCat product yet"
// blocker as every other entitlement in this file - registered now so
// wiring a real purchase check in later is a one-line change.
const kKeepBothCleanupEntitlementId = 'keep_both_cleanup';

// 2026-09-08: Tier 4 (docs/product-tiers.md) - AI Conflict Support.
// Not built - captured as an idea only. IMPORTANT if this ever gets
// built: this is the one feature in the whole app that sends vault
// content off-device to a third party (Claude/Anthropic), directly
// against LocalSync's own core "never touches a server you don't own"
// promise - see product-tiers.md's own CRITICAL section on this
// before wiring anything. Must ship with an explicit per-use "Cloud
// warning" consent dialog, never silently enabled by owning this
// entitlement alone.
const kAiConflictSupportEntitlementId = 'ai_conflict_support';

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
