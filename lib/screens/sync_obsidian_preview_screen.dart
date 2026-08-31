// screens/sync_obsidian_preview_screen.dart
//
// 2026-08-31: PKM-path sibling of sync_files_preview_screen.dart - see
// that file's header for the shared reasoning. The illustration here is
// a deliberately ABSTRACT bi-directional node/bubble graph, not any one
// PKM app's actual logo (avoids the Obsidian-branding/trademark issue
// flagged directly, while still nodding at Logseq's bubble-graph look
// alongside Obsidian's own graph view - the long-term goal is Logseq as
// the primary PKM app once it's functional enough, per direct note).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/purchase_service.dart';
import '../widgets/swap_gif_swipe_confirm.dart';
import '../widgets/shatter_page_route.dart';
import 'linking_screen.dart';
import 'paywall_obsidian_screen.dart';
import 'welcome_hero_screen.dart';

class SyncObsidianPreviewScreen extends StatelessWidget {
  const SyncObsidianPreviewScreen({super.key});

  // 2026-08-31: real gap, direct feedback - "I don't see where to pay."
  // This screen showed a "PRO - from $24.99" badge but never actually
  // charged anything - confirming the swipe just walked straight into
  // free setup. Now checks the real entitlement first (skip the
  // paywall for anyone who already owns it - never re-charge), and
  // only proceeds into the real pairing flow once actually unlocked.
  Future<void> _proceed(BuildContext context) async {
    final purchases = context.read<PurchaseService>();
    final alreadyOwned =
        await purchases.hasEntitlement(kPkmSyncEntitlementId);
    if (!context.mounted) return;

    if (!alreadyOwned) {
      final unlocked = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => PaywallObsidianScreen(purchases: purchases)),
      );
      if (unlocked != true) return; // cancelled/failed - stay put
    }

    if (!context.mounted) return;
    // This is the one real moment the pastel welcome world meets the
    // app's actual dark UI - shatters into it rather than a plain cut.
    Navigator.pushReplacement(
        context, ShatterPageRoute(builder: (_) => const LinkingScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [wBg1, Color(0xFFF1ECFA)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back, color: wInkDim),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                      color: wVioletBg,
                      borderRadius: BorderRadius.circular(4)),
                  child: Text('PRO · from \$24.99',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: wVioletDark,
                          letterSpacing: 0.5)),
                ),
                const SizedBox(height: 10),
                Text('Sync my Obsidian notes',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 26,
                        color: wInk),
                    textAlign: TextAlign.center),
                const SizedBox(height: 20),
                Expanded(
                  child: Center(
                    child: PhoneToDesktopFlow(
                      color: wVioletDark,
                      screenColor: wVioletBg,
                      travelerIcon: Icons.auto_stories_rounded,
                    ),
                  ),
                ),
                Text('Links your whole vault.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: wInkDim)),
                Text('Real conflict protection built in.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: wInkDim)),
                const SizedBox(height: 24),
                SwapGifSwipeConfirm(
                  animatedAssetPath: 'assets/gifs/progress_running.gif',
                  onConfirm: () => _proceed(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

