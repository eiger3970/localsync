// screens/upgrades_screen.dart
//
// 2026-09-26: user - "purchases are the important way in - must not be
// deep and buried, but easy and available." One tap from the main
// screen's top bar (amber badge icon), also in the kebab menu and
// Settings. Lists every purchase with its live store price, the sample
// conflict to try the conflict fixes, and Restore purchases.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/purchase_service.dart';
import '../theme.dart';
import '../widgets/demo_conflict_card.dart';
import 'paywall_conflict_picker_screen.dart';
import 'paywall_keep_both_cleanup_screen.dart';
import 'paywall_obsidian_screen.dart';
import 'rescue_screen.dart';

class UpgradesScreen extends StatefulWidget {
  const UpgradesScreen({super.key});
  @override
  State<UpgradesScreen> createState() => _UpgradesScreenState();
}

class _UpgradesScreenState extends State<UpgradesScreen> {
  final Map<String, String> _prices = {};
  final Set<String> _owned = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final purchases = context.read<PurchaseService>();
    final offerings = await purchases.getOfferings();
    for (final p in offerings?.current?.availablePackages ?? const []) {
      for (final id in [
        kKeepBothCleanupEntitlementId,
        kPkmSyncEntitlementId,
        kConflictPickerEntitlementId,
        kRescueProductId
      ]) {
        if (p.storeProduct.identifier.contains(id)) {
          _prices[id] = p.storeProduct.priceString;
        }
      }
    }
    for (final id in [
      kKeepBothCleanupEntitlementId,
      kPkmSyncEntitlementId,
      kConflictPickerEntitlementId
    ]) {
      if (await purchases.hasEntitlement(id)) _owned.add(id);
    }
    if (await purchases.hasEntitlement(kRescueEntitlementId)) _owned.add(kRescueProductId);
    if (mounted) setState(() {});
  }

  String _priceFor(String id, {String suffix = ''}) {
    if (_owned.contains(id)) return 'Owned';
    final p = _prices[id];
    return p == null ? 'Coming soon' : '$p$suffix';
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final purchases = context.read<PurchaseService>();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kVoid,
        title: Text('Upgrades', style: TextStyle(color: kStar)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 2026-10-07: Kevin - "Order these by best value at top. Income
          // incoming door must be easy for users, not hidden or obfuscated,
          // make sales the easiest part of the app with no friction." A
          // ladder, best value first (an exception to the alphabetical rule:
          // the order IS the message); each card is one tap to its purchase.
          Text('Syncing your files stays free.\nThe happier doggie is, the more is done for you :-)',
              style: TextStyle(color: kTextMid, fontSize: 14)),
          const SizedBox(height: 16),
          _UpgradeTile(
            bars: 3,
            best: true,
            icon: Icons.auto_fix_high,
            title: 'Auto merge & clean up',
            points: const ['Conflicts merged for you', 'In time order', 'Every word kept', 'Backed up first', 'Undo any merge'],
            period: 'per year · cancel anytime',
            price: _priceFor(kKeepBothCleanupEntitlementId),
            onTap: () =>
                _open(PaywallKeepBothCleanupScreen(purchases: purchases)),
          ),
          _UpgradeTile(
            bars: 2,
            icon: Icons.auto_stories_rounded,
            title: 'PKM sync',
            points: const ['Your whole Obsidian vault', 'Phone ⇄ computer', 'Kanban-safe merge'],
            period: 'once',
            price: _priceFor(kPkmSyncEntitlementId),
            onTap: () => _open(PaywallObsidianScreen(purchases: purchases)),
          ),
          _UpgradeTile(
            bars: 1,
            icon: Icons.compare_arrows,
            title: 'Visual picker',
            points: const ['Both versions side by side', 'Tap to keep one'],
            period: 'once',
            price: _priceFor(kConflictPickerEntitlementId),
            onTap: () =>
                _open(PaywallConflictPickerScreen(purchases: purchases)),
          ),
          const SizedBox(height: 8),
          _UpgradeTile(
            bars: 0,
            rescue: true,
            icon: Icons.emergency,
            title: 'Rescue package',
            points: const ['One button', 'Missing notes back', 'Every conflict cleaned up', 'Nothing deleted'],
            period: 'once · for emergencies',
            price: _priceFor(kRescueProductId),
            onTap: () => _open(const RescueScreen()),
          ),
          const SizedBox(height: 20),
          const DemoConflictCard(),
          const SizedBox(height: 20),
          Center(
            child: TextButton.icon(
              onPressed: () async {
                final info = await purchases.restorePurchases();
                if (!context.mounted) return;
                final n = info?.entitlements.active.length ?? 0;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(n > 0
                        ? 'Restored $n purchase${n == 1 ? '' : 's'}'
                        : 'Nothing to restore on this Apple Account')));
                _load();
              },
              icon: Icon(Icons.restore, color: kTextDim, size: 18),
              label: Text('Restore purchases',
                  style: TextStyle(color: kTextDim, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}

class _UpgradeTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> points; // higher tiers list more
  final String period;
  final String price;
  final VoidCallback onTap;
  final int bars; // 1-3 dog happiness levels; 0 = none (Rescue)
  final bool best;
  final bool rescue;
  const _UpgradeTile(
      {required this.icon,
      required this.title,
      required this.points,
      required this.period,
      required this.price,
      required this.onTap,
      this.bars = 0,
      this.best = false,
      this.rescue = false});

  @override
  Widget build(BuildContext context) {
    final accent = rescue ? Colors.amber : kGreen;
    final owned = price == 'Owned';
    final card = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: best ? kGreen : rescue ? Colors.amber : kBorder, width: best ? 1.6 : 1),
          boxShadow: best ? [BoxShadow(color: kGreen.withValues(alpha: 0.3), blurRadius: 14)] : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: accent, size: 22),
            const SizedBox(width: 8),
            Flexible(
              child: Text(title,
                  style: TextStyle(color: kStar, fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            if (best) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: kGreen, borderRadius: BorderRadius.circular(99)),
                child: Text('BEST', style: TextStyle(color: kVoid, fontSize: 11, fontWeight: FontWeight.w800)),
              ),
            ],
          ]),
          const SizedBox(height: 6),
          // 2026-10-07: Kevin - "points, to visualise the points included in
          // each tier, then higher tiers have more points of value".
          for (final pt in points)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(children: [
                Icon(Icons.check, color: accent, size: 16),
                const SizedBox(width: 6),
                Flexible(child: Text(pt, style: TextStyle(color: kStar, fontSize: 13))),
              ]),
            ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: Text(period, style: TextStyle(color: kTextMid, fontSize: 12))),
            // The price IS the button - one tap to buy.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                  color: owned ? Colors.transparent : accent,
                  border: Border.all(color: owned ? kTextDim : accent),
                  borderRadius: BorderRadius.circular(99)),
              child: Text(owned ? 'Owned' : price == 'Coming soon' ? price : 'Get $price',
                  style: TextStyle(color: owned ? kTextDim : kVoid, fontSize: 14, fontWeight: FontWeight.w800)),
            ),
          ]),
        ]),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        // 2026-10-07: Kevin - "the bars can change to the dog mascot ... levels
        // of happiness". 1 = sitting dog (still), 2 = walking, 3 = jumping happy.
        SizedBox(
          width: 52,
          child: bars == 0
              ? const SizedBox.shrink()
              : Image.asset(
                  bars == 3
                      ? 'assets/gifs/dog_success_stand.gif'
                      : bars == 2
                          ? 'assets/gifs/progress_running.gif'
                          : 'assets/gifs/dog_sit.png',
                  height: bars == 3 ? 66 : 36,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.none, // crisp pixel art
                ),
        ),
        const SizedBox(width: 8),
        Expanded(child: card),
      ]),
    );
  }
}
