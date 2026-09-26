// screens/upgrades_screen.dart
//
// 2026-09-26: Ken - "purchases are the important way in - must not be
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
        kConflictPickerEntitlementId
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
          Text('Syncing your files stays free. These add convenience.',
              style: TextStyle(color: kTextMid, fontSize: 13)),
          const SizedBox(height: 14),
          // 2026-09-26: Ken - "say data protection ... Someone in a panic
          // will appreciate this", as a positive statement.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.verified_user_outlined, color: kGreen, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    'Two devices edit the same note? LocalSync keeps both '
                    'versions safe. Every upgrade backs up both versions '
                    'first, so you can always restore.\n'
                    'Your data is precious. Your private data is priceless.',
                    style: TextStyle(color: kStar, fontSize: 13, height: 1.5)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Alphabetical (house rule).
          _UpgradeTile(
            icon: Icons.auto_fix_high,
            title: 'Auto merge & clean up',
            line: 'Merges conflicting notes for you, with undo',
            price: _priceFor(kKeepBothCleanupEntitlementId, suffix: ' / year'),
            onTap: () =>
                _open(PaywallKeepBothCleanupScreen(purchases: purchases)),
          ),
          _UpgradeTile(
            icon: Icons.auto_stories_rounded,
            title: 'PKM sync',
            line: 'Sync your notes app vault too',
            price: _priceFor(kPkmSyncEntitlementId),
            onTap: () => _open(PaywallObsidianScreen(purchases: purchases)),
          ),
          _UpgradeTile(
            icon: Icons.compare_arrows,
            title: 'Visual picker',
            line: 'See both versions side by side, tap to keep',
            price: _priceFor(kConflictPickerEntitlementId),
            onTap: () =>
                _open(PaywallConflictPickerScreen(purchases: purchases)),
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
  final String line;
  final String price;
  final VoidCallback onTap;
  const _UpgradeTile(
      {required this.icon,
      required this.title,
      required this.line,
      required this.price,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: kSurface, border: Border.all(color: kBorder)),
        child: Row(
          children: [
            Icon(icon, color: kGreen, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: kStar,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(line, style: TextStyle(color: kTextMid, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(price,
                style: TextStyle(
                    color: price == 'Owned' ? kTextDim : kGreen,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
