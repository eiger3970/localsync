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
  // 2026-08-28: real feedback, live - "smoother" for this exact widget,
  // given its own 2026-08-18 spec (small, always-visible, "fries with
  // that", NOT naggy) means fixing the one thing that spec doesn't
  // cover: a real-looking "$24.99" next to a button that can never be
  // pressed (no RevenueCat product configured yet - see
  // purchase_service.dart) reads as broken, not honest. This distinguishes
  // "still checking" from "checked, nothing to sell yet" so the button
  // slot can show a quiet coming-soon state instead of a dead price.
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _loadOffering();
  }

  Future<void> _loadOffering() async {
    final offerings = await widget.purchases.getOfferings();
    final package = offerings?.current?.availablePackages
        .where((p) =>
            p.storeProduct.identifier.contains(kPkmSyncEntitlementId))
        .firstOrNull;
    if (!mounted) return;
    if (package == null) {
      setState(() => _checked = true);
      return;
    }
    setState(() {
      _package = package;
      _priceLabel = package.storeProduct.priceString;
      _checked = true;
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
          builder: (_) =>
              PaywallObsidianScreen(purchases: widget.purchases)),
    );
    if (unlocked == true) widget.onUnlocked();
  }

  @override
  Widget build(BuildContext context) {
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
              if (_package != null)
                OutlinedButton(
                  onPressed: _openPaywall,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: kGreen),
                    foregroundColor: kGreen,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                  ),
                  child: Text(_priceLabel!,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                )
              else if (_checked)
                // No real product configured yet (purchase_service.dart -
                // no funded Apple Developer account/RevenueCat product).
                // A quiet, non-interactive label instead of a fake price
                // on a dead button - reads as "not yet available", not
                // "broken".
                Text('Coming soon',
                    style: TextStyle(
                        color: kTextDim,
                        fontSize: 11,
                        fontStyle: FontStyle.italic)),
            ],
          ),
        ],
      ),
    );
  }
}
