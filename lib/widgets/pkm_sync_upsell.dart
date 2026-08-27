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

class PkmSyncUpsell extends StatefulWidget {
  final PurchaseService purchases;
  final VoidCallback onUnlocked;
  const PkmSyncUpsell(
      {super.key, required this.purchases, required this.onUnlocked});

  @override
  State<PkmSyncUpsell> createState() => _PkmSyncUpsellState();
}

class _PkmSyncUpsellState extends State<PkmSyncUpsell> {
  bool _busy = false;
  String? _error;
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
        .where((p) =>
            p.storeProduct.identifier.contains(kPkmSyncEntitlementId))
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
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final info = await widget.purchases.purchasePackage(package);
      final unlocked =
          info?.entitlements.active.containsKey(kPkmSyncEntitlementId) ??
              false;
      if (!mounted) return;
      if (unlocked) {
        // Real purchase confirmed - run the actual vault-linking
        // sequence now, the same one SyncChoiceScreen's "My Obsidian
        // notes" choice already leads to. Not a lesser/separate path.
        widget.onUnlocked();
      } else {
        setState(() => _error = 'Purchase did not complete - try again.');
      }
    } on PurchasesErrorCode catch (_) {
      if (mounted) setState(() => _error = 'Purchase cancelled or failed.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Purchase cancelled or failed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
              _busy
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: kGreen),
                    )
                  : OutlinedButton(
                      onPressed: _package == null ? null : _buy,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: kGreen),
                        foregroundColor: kGreen,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                      ),
                      child: Text(_priceLabel ?? r'$24.99',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 11.5)),
          ],
        ],
      ),
    );
  }
}
