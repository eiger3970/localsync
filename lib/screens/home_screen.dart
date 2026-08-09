// screens/home_screen.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
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
            icon: const Icon(Icons.more_vert, color: kTeal, size: 22),
            onSelected: (v) {
              if (v == 'pair') _openPairing(context);
              if (v == 'link') _openLinking(context);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'pair',
                child: Row(
                  children: const [
                    Icon(Icons.vpn_key_outlined, color: kStar, size: 18),
                    SizedBox(width: 12),
                    Text('Pair with desktop',
                        style: TextStyle(color: kStar, fontSize: 14)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'link',
                child: Row(
                  children: const [
                    Icon(Icons.phone_iphone, color: kStar, size: 18),
                    SizedBox(width: 12),
                    Text('Set up a vault',
                        style: TextStyle(color: kStar, fontSize: 14)),
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
              child: CircularProgressIndicator(color: kTeal, strokeWidth: 1),
            );
          }
          if (provider.repos.isEmpty) {
            return _EmptyState(
              onAdd:     () => _openAddRepo(context),
              onSetup:   () => _openLinking(context),
            );
          }
          return ListView.separated(
            itemCount: provider.repos.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: kBorder),
            itemBuilder: (_, i) => _RepoTile(
              repo: provider.repos[i],
              onSync: () =>
                  provider.syncRepository(provider.repos[i].id!),
              onCommit: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      CommitScreen(repo: provider.repos[i]),
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openAddRepo(context),
        backgroundColor: kTeal,
        foregroundColor: kVoid,
        shape: const RoundedRectangleBorder(),
        child: const Icon(Icons.add),
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
            desktopIp:   '172.20.10.11',
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
  final Repository      repo;
  final VoidCallback    onSync;
  final VoidCallback    onCommit;
  final VoidCallback    onToggleAutoSync;
  final VoidCallback    onDelete;

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
                    child:
                        const Icon(Icons.sync, color: kTeal, size: 22),
                  ),
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              color: kSurface,
              icon: const Icon(Icons.more_vert,
                  color: kTextDim, size: 18),
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
                      style:
                          TextStyle(color: Colors.redAccent, fontSize: 15)),
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
      child: const Icon(Icons.sync, color: kTeal, size: 22),
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
        color: kTeal,
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
      return Text(
        reason,
        style: const TextStyle(color: Colors.redAccent, fontSize: 13),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (repo.lastSync != null)
          Text(
            'synced ${_timeAgo(repo.lastSync!)}',
            style: const TextStyle(
                color: kTextDim, fontSize: 12, letterSpacing: 0.5),
          ),
        if (repo.fileCount > 0)
          Text(
            '${repo.fileCount} files · ${repo.folderCount} folders',
            style: const TextStyle(
                color: kTextDim, fontSize: 12, letterSpacing: 0.5),
          ),
      ],
    );
  }

  String _timeAgo(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60)  return 'just now';
    if (d.inMinutes < 60)  return '${d.inMinutes}m ago';
    if (d.inHours < 24)    return '${d.inHours}h ago';
    return '${d.inDays}d ago';
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
        color: autoSync ? kTeal.withOpacity(0.15) : kBorder,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        autoSync ? 'AUTO' : 'MANUAL',
        style: TextStyle(
          color: autoSync ? kTeal : kTextDim,
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
      SyncStatus.ok      => kTeal,
      SyncStatus.syncing => Colors.amber,
      SyncStatus.error   => Colors.redAccent,
      SyncStatus.idle    => kTextDim,
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
    final hasError   = repos.any((r) => r.status == SyncStatus.error);
    final hasSyncing = repos.any((r) => r.status == SyncStatus.syncing);
    final allOk      = repos.every((r) => r.status == SyncStatus.ok);

    if (hasSyncing) return const Icon(Icons.sync,                color: Colors.amber,     size: 22);
    if (hasError)   return const Icon(Icons.error_outline,       color: Colors.redAccent, size: 22);
    if (allOk)      return const Icon(Icons.check_circle_outline, color: kTeal,           size: 22);
    return           const Icon(Icons.circle_outlined,           color: kTextDim,         size: 22);
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  final VoidCallback onSetup;
  const _EmptyState({required this.onAdd, required this.onSetup});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('↕', style: TextStyle(fontSize: 48, color: kTextDim)),
            const SizedBox(height: 16),
            const Text('No repositories',
                style: TextStyle(
                    color: kStar, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text(
              'First time? Set up your vault to connect your phone to your desktop.',
              style: TextStyle(color: kTextDim, fontSize: 11, height: 1.6),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // Primary: SET UP VAULT
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onSetup,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kTeal,
                  foregroundColor: kVoid,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: const RoundedRectangleBorder(),
                  textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2),
                ),
                child: const Text('SET UP VAULT'),
              ),
            ),
            const SizedBox(height: 12),
            // Secondary: manual add
            TextButton(
              onPressed: onAdd,
              child: const Text(
                'ADD EXISTING REPOSITORY',
                style: TextStyle(
                    color: kTextDim, fontSize: 10, letterSpacing: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
