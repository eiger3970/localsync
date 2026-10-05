// widgets/pkm_sync_upsell.dart
//
// 2026-08-27: real feedback, live - "the free app can then setup
// obsidian with the special recipe algorithm... running through the
// obsidian install once an IAP is paid." Tier 0 (free, plain file sync)
// is the whole app for a normie today; this is how they reach Tier 1
// (Obsidian/PKM sync) from inside it - not a separate download, not a
// separate setup path, the SAME vault-linking sequence
// (linking_controller.dart) already built and real-device tested,
// triggered by a real purchase instead of the free chooser screen.
//
// Same proven shape as conflict_picker_upsell.dart (that file's own
// header explains why it's not wired anywhere yet - no funded Apple
// Developer account/RevenueCat product) - _package staying null just
// disables the button, no fake/broken purchase flow, same honesty this
// whole app already holds every other IAP surface to.

import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../theme.dart';
import '../services/purchase_service.dart';
import '../screens/paywall_obsidian_screen.dart';

class PkmSyncUpsell extends StatefulWidget {
  final PurchaseService purchases;
  final VoidCallback onUnlocked;
  const PkmSyncUpsell(
      {super.key, required this.purchases, required this.onUnlocked});

  @override
  State<PkmSyncUpsell> createState() => _PkmSyncUpsellState();
}

class _PkmSyncUpsellState extends State<PkmSyncUpsell> {
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
        .where((p) => p.storeProduct.identifier.contains(kPkmSyncEntitlementId))
        .firstOrNull;
    if (!mounted) return;
    if (package == null) return;
    setState(() {
      _package = package;
      _priceLabel = package.storeProduct.priceString;
    });
  }

  // 2026-08-31: this small card stays exactly the quiet, always-visible,
  // non-naggy nudge it was designed to be - it still just sits there
  // doing nothing until tapped. Tapping the price now opens the fuller
  // paywall (benefit list, one clear price) before actually charging,
  // instead of purchasing inline the instant the card is touched.
  Future<void> _openPaywall() async {
    final unlocked = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => PaywallObsidianScreen(purchases: widget.purchases)),
    );
    if (unlocked == true) widget.onUnlocked();
  }

  @override
  Widget build(BuildContext context) {
    // 2026-10-05: user - no "Coming soon" teaser cards: the card shows only
    // once the store returns a real price (sideloaded builds never do, and
    // App Review rejects placeholder features).
    if (_package == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurface,
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_stories_rounded, color: kGreen, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sync your Obsidian vault too',
                        style: TextStyle(
                            color: kStar,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      'One-time unlock - Kanban-safe conflict merge, '
                      'nothing ever silently lost',
                      style: TextStyle(color: kTextMid, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: _openPaywall,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: kGreen),
                  foregroundColor: kGreen,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
                child: Text(_priceLabel!,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
              )
            ],
          ),
        ],
      ),
    );
  }
}
