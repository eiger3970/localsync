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
// 2026-09-17: real App ID/ad unit ID below, from the user's own AdMob
// console (Apps -> LocalSync) - replaces Google's published TEST
// values this held since 2026-09-16. Info.plist's
// GADApplicationIdentifier carries the matching real App ID - both
// updated together, they're a pair.
import 'package:google_mobile_ads/google_mobile_ads.dart';

const String kBannerAdUnitId = 'ca-app-pub-5706552645183213/2047904758';

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
