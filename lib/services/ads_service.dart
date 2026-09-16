// services/ads_service.dart
//
// 2026-09-16: free-tier monetization - "Ads without tracking, go for
// free app." Free tier only (paid tier stays 100% ad-free, matching
// this app's own privacy pitch - see the widget wiring in
// pkm_sync_upsell's neighbor, home_screen.dart, for where this is
// gated to Tier 0/genericFolder repos only).
//
// Non-personalized/contextual ads only: AdRequest(nonPersonalizedAds:
// true) below means this never touches IDFA, never triggers the App
// Tracking Transparency prompt, and does no cross-app behavioral
// tracking - the ad server picks an ad based on the ad slot/app
// category, not the user's own history. This is a real, documented
// AdMob mode (developers.google.com/admob/ios/targeting), not a
// workaround - confirmed via Google's own Flutter SDK docs before
// building this.
//
// Real App ID/ad unit ID below are Google's own published TEST values
// (developers.google.com/admob/ios/test-ads) - always return real test
// ads, safe to ship in a dev build, but must be swapped for a real
// AdMob account's own IDs before this app is ever actually submitted.
// Info.plist's GADApplicationIdentifier carries the matching test App
// ID - both need updating together, they're a pair.
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// TODO real AdMob account: replace with the real banner ad unit ID
/// once one exists (see this file's own doc above for the pairing
/// with Info.plist's GADApplicationIdentifier).
const String kBannerAdUnitId = 'ca-app-pub-3940256099942544/2435281174';

class AdsService {
  static bool _initialized = false;

  /// Idempotent - safe to call from multiple places (e.g. every time
  /// the free-tier home screen builds) without re-initializing the SDK.
  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;
    await MobileAds.instance.initialize();
  }

  static AdRequest nonPersonalizedRequest() =>
      const AdRequest(nonPersonalizedAds: true);
}
