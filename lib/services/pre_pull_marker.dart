import 'dart:io';

/// 2026-11-14: written by every pull (sync_service.dart notePrePull): the phone's commit from before the pull. A note
/// saved within 15 min that drops every line the pull added is treated as Obsidian writing its OLD copy and is merged
/// by git (mergeStaleSavesWithGit).
const kPrePullFile = 'localsync_pre_pull_head';

/// 2026-11-14 owner, real test: "After conflict and push the desktop should show the phone's entry". Picking
/// "phone again" in Conflicts removed the computer's line, which looked exactly like an old Obsidian copy, so the pick
/// was merged again and the computer's line came back. A choice made in Conflicts is deliberate: it clears the marker.
void clearPrePullMarker(String vaultPath) {
  try {
    final f = File('$vaultPath/.git/$kPrePullFile');
    if (f.existsSync()) f.deleteSync();
  } catch (_) {}
}
