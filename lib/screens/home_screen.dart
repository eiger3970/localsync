// screens/home_screen.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../constants.dart';
import '../models/repository.dart';
import '../services/repository_provider.dart';
import 'add_repository_screen.dart';
import 'commit_screen.dart';
import 'linking_screen.dart';
import 'pairing_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SYNCLOCAL'),
        actions: [
          // Fixed 2026-08-09: two bare icon buttons (key, phone) with only
          // a long-press tooltip for explanation - on iOS a tap doesn't
          // show the tooltip at all, so neither icon was actually self-
          // explanatory at a glance. User's own words: "Key and phone
          // image, why, if yes, make clearer." Consolidated into one menu
          // with real text labels - still fully reachable (re-pairing a
          // new phone, or linking an additional vault, are both genuine
          // ongoing needs, not first-run-only), just not two unexplained
          // icons sitting permanently in the app bar.
          PopupMenuButton<String>(
            color: kSurface,
            icon: const Icon(Icons.more_vert, color: kGreen, size: 22),
            onSelected: (v) {
              if (v == 'pair') _openPairing(context);
              if (v == 'link') _openLinking(context);
            },
            // 2026-08-11: labels alone still drew "why are these
            // needed?" on real device review - added a one-line reason
            // under each so the menu explains itself without relying on
            // a tooltip (already known not to fire on iOS tap, see the
            // fix note above) or a chat explanation the user won't have
            // open next time they wonder.
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'pair',
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: const [
                    Icon(Icons.vpn_key_outlined, color: kStar, size: 18),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Pair with desktop',
                              style: TextStyle(color: kStar, fontSize: 14)),
                          Text('New phone, or lost connection',
                              style: TextStyle(color: kTextMid, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'link',
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(Icons.phone_iphone, color: kStar, size: 18),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Set up a $kContainerName',
                              style: TextStyle(color: kStar, fontSize: 14)),
                          Text('Link another $kContainerName to this phone',
                              style: TextStyle(color: kTextMid, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Consumer<RepositoryProvider>(
            builder: (_, p, __) => Padding(
              padding: const EdgeInsets.only(right: 16),
              child: _StatusIcon(repos: p.repos),
            ),
          ),
        ],
      ),
      body: Consumer<RepositoryProvider>(
        builder: (_, provider, __) {
          if (provider.loading) {
            return const Center(
              child: CircularProgressIndicator(color: kGreen, strokeWidth: 1),
            );
          }
          if (provider.repos.isEmpty) {
            return _EmptyState(onSetup: () => _openLinking(context));
          }
          return ListView.separated(
            itemCount: provider.repos.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: kBorder),
            itemBuilder: (_, i) => _RepoTile(
              repo: provider.repos[i],
              onSync: () => provider.syncRepository(provider.repos[i].id!),
              onCommit: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CommitScreen(repo: provider.repos[i]),
                ),
              ),
              onToggleAutoSync: () =>
                  provider.toggleAutoSync(provider.repos[i].id!),
              onDelete: () =>
                  _confirmDelete(context, provider, provider.repos[i]),
            ),
          );
        },
      ),
      // 2026-08-11: a bare "+" still drew "what is this for?" even after
      // removing its on-screen duplicate - a label fixes that directly,
      // and doesn't depend on a tooltip (doesn't fire on iOS tap).
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddRepo(context),
        backgroundColor: kGreen,
        foregroundColor: kVoid,
        shape: const RoundedRectangleBorder(),
        icon: const Icon(Icons.add),
        label: const Text('ADD MANUALLY',
            style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1)),
      ),
    );
  }

  void _openAddRepo(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AddRepositoryScreen()),
      );

  void _openPairing(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const PairingScreen(
            desktopUser: 'rapi5',
            desktopIp: '172.20.10.11',
          ),
        ),
      );

  void _openLinking(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LinkingScreen()),
      );

  Future<void> _confirmDelete(
    BuildContext context,
    RepositoryProvider provider,
    Repository repo,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('Remove repository',
            style: TextStyle(color: kStar, fontSize: 17)),
        content: Text(
          'Remove "${repo.name}"? Files are not deleted.',
          style: const TextStyle(color: kTextMid, fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: kTextDim, fontSize: 15)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove',
                style: TextStyle(color: Colors.redAccent, fontSize: 15)),
          ),
        ],
      ),
    );
    if (confirmed == true && repo.id != null) {
      await provider.removeRepository(repo.id!);
    }
  }
}

// ── Repo tile ──────────────────────────────────────────────────────────────────

class _RepoTile extends StatelessWidget {
  final Repository repo;
  final VoidCallback onSync;
  final VoidCallback onCommit;
  final VoidCallback onToggleAutoSync;
  final VoidCallback onDelete;

  const _RepoTile({
    required this.repo,
    required this.onSync,
    required this.onCommit,
    required this.onToggleAutoSync,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isSyncing = repo.status == SyncStatus.syncing;

    return GestureDetector(
      onLongPress: onCommit,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        title: Row(
          children: [
            _StatusDot(status: repo.status),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        repo.name,
                        style: const TextStyle(
                            color: kStar,
                            fontSize: 16,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      _AutoBadge(autoSync: repo.autoSync),
                    ],
                  ),
                  const SizedBox(height: 4),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: isSyncing
                        ? _PhaseText(
                            key: ValueKey(repo.syncPhase),
                            label: repo.syncPhase.label,
                          )
                        : _MetaText(repo: repo),
                  ),
                ],
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            isSyncing
                ? const _SpinningSync()
                : GestureDetector(
                    onTap: onSync,
                    child: const Icon(Icons.sync, color: kGreen, size: 22),
                  ),
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              color: kSurface,
              icon: const Icon(Icons.more_vert, color: kTextDim, size: 18),
              onSelected: (v) {
                if (v == 'commit') onCommit();
                if (v == 'toggle_auto') onToggleAutoSync();
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'commit',
                  child: Text('Commit & push',
                      style: TextStyle(color: kStar, fontSize: 15)),
                ),
                PopupMenuItem(
                  value: 'toggle_auto',
                  child: Text(
                    repo.autoSync ? 'Switch to manual' : 'Switch to auto',
                    style: const TextStyle(color: kStar, fontSize: 15),
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Remove',
                      style: TextStyle(color: Colors.redAccent, fontSize: 15)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Spinning sync icon ─────────────────────────────────────────────────────────

class _SpinningSync extends StatefulWidget {
  const _SpinningSync();

  @override
  State<_SpinningSync> createState() => _SpinningSyncState();
}

class _SpinningSyncState extends State<_SpinningSync>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => Transform.rotate(
        angle: _ctrl.value * 2 * math.pi,
        child: child,
      ),
      child: const Icon(Icons.sync, color: kGreen, size: 22),
    );
  }
}

// ── Phase text ─────────────────────────────────────────────────────────────────

class _PhaseText extends StatelessWidget {
  final String label;
  const _PhaseText({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: kGreen,
        fontSize: 12,
        letterSpacing: 0.5,
        fontStyle: FontStyle.italic,
      ),
    );
  }
}

// ── Static meta text ───────────────────────────────────────────────────────────

class _MetaText extends StatelessWidget {
  final Repository repo;
  const _MetaText({required this.repo});

  @override
  Widget build(BuildContext context) {
    if (repo.status == SyncStatus.error && repo.lastError != null) {
      final reason = repo.lastError!.split('\n').first;
      // Fixed 2026-08-09: this used to show only the first line,
      // truncated, with no way to see the rest - real device feedback
      // was a dead end ("I see no suggestions on next steps"). The full
      // lastError now carries diagnosis + resolution + (when available)
      // the raw exception text; tapping reveals all of it instead of
      // silently discarding everything past the first line.
      return GestureDetector(
        onTap: () => _showFullError(context, repo.lastError!),
        child: Row(
          children: [
            Expanded(
              child: Text(
                reason,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.info_outline, color: Colors.redAccent, size: 14),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (repo.lastSync != null)
          Text(
            'synced ${_timeAgo(repo.lastSync!)}',
            style: const TextStyle(
                color: kTextMid, fontSize: 14, letterSpacing: 0.3),
          ),
        if (repo.fileCount > 0)
          Text(
            '${repo.fileCount} files · ${repo.folderCount} folders',
            style: const TextStyle(
                color: kTextMid, fontSize: 14, letterSpacing: 0.3),
          ),
      ],
    );
  }

  String _timeAgo(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  void _showFullError(BuildContext context, String fullError) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('Sync error',
            style: TextStyle(color: kStar, fontSize: 17)),
        content: SingleChildScrollView(
          child: Text(fullError,
              style:
                  const TextStyle(color: kTextMid, fontSize: 14, height: 1.6)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close',
                style: TextStyle(color: kGreen, fontSize: 15)),
          ),
        ],
      ),
    );
  }
}

// ── Auto/manual badge ──────────────────────────────────────────────────────────

class _AutoBadge extends StatelessWidget {
  final bool autoSync;
  const _AutoBadge({required this.autoSync});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: autoSync ? kGreen.withOpacity(0.15) : kBorder,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        autoSync ? 'AUTO' : 'MANUAL',
        style: TextStyle(
          color: autoSync ? kGreen : kTextDim,
          fontSize: 8,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ── Status dot ─────────────────────────────────────────────────────────────────

class _StatusDot extends StatelessWidget {
  final SyncStatus status;
  const _StatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      SyncStatus.ok => kGreen,
      SyncStatus.syncing => Colors.amber,
      SyncStatus.error => Colors.redAccent,
      SyncStatus.idle => kTextDim,
    };
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

// ── Top-right status icon ──────────────────────────────────────────────────────

class _StatusIcon extends StatelessWidget {
  final List<Repository> repos;
  const _StatusIcon({required this.repos});

  @override
  Widget build(BuildContext context) {
    if (repos.isEmpty) return const SizedBox.shrink();
    final hasError = repos.any((r) => r.status == SyncStatus.error);
    final hasSyncing = repos.any((r) => r.status == SyncStatus.syncing);
    final allOk = repos.every((r) => r.status == SyncStatus.ok);

    if (hasSyncing)
      return const Icon(Icons.sync, color: Colors.amber, size: 22);
    if (hasError)
      return const Icon(Icons.error_outline, color: Colors.redAccent, size: 22);
    if (allOk)
      return const Icon(Icons.check_circle_outline, color: kGreen, size: 22);
    return const Icon(Icons.circle_outlined, color: kTextDim, size: 22);
  }
}

// ── Icon box (matching padding+border on both drag glyphs) ──────────────────────

// 2026-08-11: gives both drag icons an identical layout box regardless
// of hover state, so the drop target's border doesn't push it out of
// vertical alignment with the drag source - same fix as the vault-setup
// screen's _DeviceGlyph alignment bug.
class _IconBox extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color color;
  final bool hovering;
  const _IconBox({
    required this.icon,
    required this.size,
    required this.color,
    this.hovering = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        border: Border.all(
          color: hovering ? kGreen : Colors.transparent,
          width: 2,
        ),
      ),
      child: Icon(icon, size: size, color: color),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyState extends StatefulWidget {
  final VoidCallback onSetup;
  const _EmptyState({required this.onSetup});

  @override
  State<_EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<_EmptyState>
    with SingleTickerProviderStateMixin {
  bool _dragHover = false;
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    // 2026-08-11: subtle continuous pulse on the draggable icon so the
    // drag gesture is discoverable at a glance - there's no button left
    // to fall back on now that SET UP VAULT was removed per explicit
    // user direction, so the icon itself has to read as interactive.
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 2026-08-11: "enlarge to max size per device so there's some
    // padding space on the left and right edges" - sized from the real
    // screen width instead of a fixed guess, same approach as the
    // vault-setup screen. Both icons wrapped in a matching padding+
    // border box (transparent unless hovered) so they sit at identical
    // heights regardless of the drop target's hover border - a fixed
    // guess here previously caused a real vertical-alignment mismatch
    // on the vault-setup screen once sizes changed.
    // 2026-08-11: "images too large, the notebook... past the screen's
    // edge" - real overflow bug, not just a size preference. The Row
    // was nested inside this screen's own 32px-per-side Padding *and*
    // its own separate edgePadding, but iconSize was only computed
    // against the inner padding - so the real available width was 32px
    // per side narrower than what the icons were sized for. Fixed by
    // giving the Row its own (smaller) padding directly, matching the
    // pattern already used on the vault-setup screen, with the size
    // formula now matching the padding actually applied.
    final screenWidth = MediaQuery.of(context).size.width;
    const rowPadding = 16.0;
    const arrowSection = 70.0;
    final iconSize =
        ((screenWidth - rowPadding * 2 - arrowSection) / 2).clamp(70.0, 170.0);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 2026-08-11: real device review - "make main image larger,
          // perhaps at top... this is the top priority for a user, the
          // rest is sub information." The standalone sync_alt icon
          // that used to lead this screen was dropped ("why are the
          // left/right arrows here?" - once the real action moved
          // in front of it, it read as unexplained decoration rather
          // than information). The drag pictogram - the actual
          // action - now leads instead. onSetup here just opens the
          // vault-setup screen (same navigation the old SET UP VAULT
          // button did) - the real download only starts once inside
          // it.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: rowPadding),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Draggable<bool>(
                  data: true,
                  feedback: Material(
                    color: Colors.transparent,
                    child: Opacity(
                      opacity: 0.85,
                      child: _IconBox(
                        icon: Icons.computer_rounded,
                        size: iconSize,
                        color: kGreen,
                      ),
                    ),
                  ),
                  childWhenDragging: Opacity(
                    opacity: 0.3,
                    child: _IconBox(
                      icon: Icons.computer_rounded,
                      size: iconSize,
                      color: kTextMid,
                    ),
                  ),
                  child: AnimatedBuilder(
                    animation: _pulseCtrl,
                    builder: (_, child) => Opacity(
                      opacity: 0.6 + (_pulseCtrl.value * 0.4),
                      child: child,
                    ),
                    child: _IconBox(
                      icon: Icons.computer_rounded,
                      size: iconSize,
                      color: kGreen,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(Icons.arrow_forward_rounded,
                      color: kTextDim, size: 34),
                ),
                DragTarget<bool>(
                  onWillAcceptWithDetails: (_) {
                    setState(() => _dragHover = true);
                    return true;
                  },
                  onLeave: (_) => setState(() => _dragHover = false),
                  onAcceptWithDetails: (_) {
                    setState(() => _dragHover = false);
                    widget.onSetup();
                  },
                  builder: (context, candidate, rejected) => _IconBox(
                    icon: Icons.auto_stories_rounded,
                    size: iconSize,
                    color: kTextMid,
                    hovering: _dragHover,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                const SizedBox(height: 18),
                const Text('Drag to set up your vault',
                    style:
                        TextStyle(color: kTextMid, fontSize: 14, height: 1.5),
                    textAlign: TextAlign.center),
                const SizedBox(height: 40),
                // 2026-08-11: "make the 0 clear... unsure what to do
                // with this image" persisted even after enlarging the
                // badge - the cramped corner-overlay badge was the
                // real problem, not its size. Replaced with a plain
                // inline readout instead: icon, then the count itself
                // at a real readable size, then the caption - nothing
                // overlapping, nothing to interpret. Caption color
                // fixed from kTextDim to kTextMid ("text colour is
                // inconsistent") - this page's secondary text
                // (drag hint, kebab subtitles) is consistently
                // kTextMid, kTextDim was a stray third shade. Also
                // now says "PKM vaults" not just "vaults" - "what is
                // a vault?" plus explicit direction to match page 2's
                // wording.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.source_outlined,
                        size: 24, color: kTextMid),
                    const SizedBox(width: 10),
                    const Text('0',
                        style: TextStyle(
                            color: kTextMid,
                            fontSize: 18,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(width: 6),
                    Text('$kGenericAppLabel ${kContainerName}s linked',
                        style: const TextStyle(color: kTextMid, fontSize: 13)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
