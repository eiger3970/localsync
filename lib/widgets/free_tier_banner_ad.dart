// widgets/free_tier_banner_ad.dart
//
// 2026-09-16: free-tier monetization - see ads_service.dart's own doc
// for the non-personalized/contextual reasoning (no IDFA, no ATT
// prompt, no tracking) and the test-ID-until-real-account note. Wired
// into home_screen.dart for Tier 0 (genericFolder) repos only, same
// gating PkmSyncUpsell already uses - paid/Obsidian-tier repos never
// see this at all, matching the decided paid-tier-stays-ad-free split.
//
// Fails silent (SizedBox.shrink) on any load error - an ad that
// doesn't load is a lost impression, not something worth surfacing to
// the user with an error state; nothing else on this screen depends
// on it.

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/ads_service.dart';

class FreeTierBannerAd extends StatefulWidget {
  const FreeTierBannerAd({super.key});

  @override
  State<FreeTierBannerAd> createState() => _FreeTierBannerAdState();
}

class _FreeTierBannerAdState extends State<FreeTierBannerAd> {
  BannerAd? _bannerAd;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await AdsService.ensureInitialized();
    final ad = BannerAd(
      size: AdSize.banner,
      adUnitId: kBannerAdUnitId,
      request: AdsService.nonPersonalizedRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
    );
    _bannerAd = ad;
    await ad.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _bannerAd == null) return const SizedBox.shrink();
    return SizedBox(
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }
}
