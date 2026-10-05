// widgets/folder_route_view.dart
//
// 2026-09-24: real feedback, live - "My eyes are bleeding from
// overwhelming text. Can you add svg imagery and be less verbose." A
// folder route drawn as a small tree - one row per tap, an icon per
// row, indented one step deeper each time - instead of a sentence of
// "Home Screen > Files app (blue folder icon) > On My iPhone > ...".
// Material icons (vector, same icon language as the rest of the app),
// no emoji. The Files row uses the Files app's own blue so someone
// coming from cloud-only use can spot the real icon on their Home
// Screen.

import 'package:flutter/material.dart';
import '../theme.dart';

enum CrumbKind {
  home, filesApp, device, cloud, folder, vault, backup, wrong,
  // 2026-09-30: routes inside LocalSync itself (Backups screen).
  app, menu, screen
}

class Crumb {
  final String label;
  final CrumbKind kind;
  /// Indent level; null = one deeper than the row above. Siblings (e.g.
  /// several vaults inside one folder) pass the same depth.
  final int? depth;
  const Crumb(this.label, this.kind, {this.depth});
}

/// Turns a filesAppRoute() list (e.g. ['On My iPhone', 'Obsidian',
/// 'My vault']) into crumbs; [vaultIndex] marks which one is the vault.
List<Crumb> crumbsFromRoute(List<String> route, {int? vaultIndex}) => [
      for (var i = 0; i < route.length; i++)
        Crumb(
            route[i],
            i == 0
                ? (route[i] == 'iCloud Drive' ? CrumbKind.cloud : CrumbKind.device)
                : i == vaultIndex
                    ? CrumbKind.vault
                    : CrumbKind.folder),
    ];

/// 2026-09-30: where a full copy is found - it sits in the vault's hidden
/// .localsync_backups folder (vault_backup.dart, kFullBackupsFolder), which
/// the Files app doesn't show, so the route goes through LocalSync's own
/// Backups screen.
List<Crumb> fullBackupCrumbs(String backupName) => [
      const Crumb('Phone home screen', CrumbKind.home),
      const Crumb('LocalSync', CrumbKind.app),
      const Crumb('Menu', CrumbKind.menu),
      const Crumb('Backups', CrumbKind.screen),
      Crumb(backupName, CrumbKind.backup),
    ];

class FolderRouteView extends StatelessWidget {
  final List<Crumb> crumbs;
  const FolderRouteView(this.crumbs, {super.key});

  static const _filesBlue = kFilesBlue;

  static (IconData, Color) _look(CrumbKind k) => switch (k) {
        CrumbKind.home => (Icons.home_outlined, kTextMid),
        CrumbKind.filesApp => (Icons.folder, _filesBlue),
        CrumbKind.device => (Icons.phone_iphone, kTextMid),
        CrumbKind.cloud => (Icons.cloud_outlined, kTextMid),
        CrumbKind.folder => (Icons.folder_outlined, kTextMid),
        CrumbKind.vault => (Icons.folder_special_outlined, kGreen),
        CrumbKind.backup => (Icons.shield_outlined, kGreen),
        CrumbKind.wrong => (Icons.folder_off_outlined, Colors.redAccent),
        CrumbKind.app => (Icons.sync, kGreen),
        CrumbKind.menu => (Icons.more_vert, kTextMid),
        CrumbKind.screen => (Icons.history, kTextMid),
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < crumbs.length; i++)
          Padding(
            padding: EdgeInsets.only(
                left: (crumbs[i].depth ?? i) * 12.0, top: i == 0 ? 0 : 4),
            child: Row(
              children: [
                if (i > 0)
                  Icon(Icons.subdirectory_arrow_right,
                      size: 14, color: kTextDim),
                if (i > 0) const SizedBox(width: 2),
                Icon(_look(crumbs[i].kind).$1,
                    size: 18, color: _look(crumbs[i].kind).$2),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    crumbs[i].label,
                    style: TextStyle(
                      color: i == crumbs.length - 1 ? kStar : kTextMid,
                      fontSize: 13,
                      fontWeight: i == crumbs.length - 1
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
