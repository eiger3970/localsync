// services/desktop_schedule.dart
//
// 2026-09-25: real ask, live - "Your desktop syncs by itself every 5
// minutes... may cause concern about wasting computer power or not having
// 100% control of their own personal desktop. I guess there's no controls
// or options here to give a picky user a manual control?" There weren't:
// the desktop cron line was hardcoded to every 5 minutes. Settings ->
// DESKTOP SYNC now picks every 5 minutes, every hour, or manual only
// (no cron line at all - the Desktop sync button still runs it on demand).
// Saved on this phone; written to the desktop's crontab over SSH.
import 'package:shared_preferences/shared_preferences.dart';

enum DesktopSchedule { every5min, hourly, manual }

const _kDesktopScheduleKey = 'desktop_sync_schedule';

extension DesktopScheduleLabel on DesktopSchedule {
  String get label => switch (this) {
        DesktopSchedule.every5min => 'Every 5 minutes',
        DesktopSchedule.hourly => 'Every hour',
        DesktopSchedule.manual => 'Only when I tap Desktop sync',
      };

  /// The crontab time field, or null for manual (no cron line).
  String? get cron => switch (this) {
        DesktopSchedule.every5min => '*/5 * * * *',
        DesktopSchedule.hourly => '0 * * * *',
        DesktopSchedule.manual => null,
      };
}

Future<DesktopSchedule> loadDesktopSchedule() async {
  final prefs = await SharedPreferences.getInstance();
  final name = prefs.getString(_kDesktopScheduleKey);
  return DesktopSchedule.values.firstWhere((s) => s.name == name,
      orElse: () => DesktopSchedule.every5min);
}

Future<void> saveDesktopSchedule(DesktopSchedule s) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kDesktopScheduleKey, s.name);
}

/// Shell command that replaces THIS repo's LocalSync crontab line on the
/// desktop, then adds it back unless [schedule] is manual. [escapedRepo]
/// and [vaultEnv] are already shell-quoted, same as the callers built them.
///
/// 2026-09-25: used to drop EVERY localsync_sync.sh line - so setting up a
/// second vault/folder on the same desktop (Ken's free-version test next to
/// his real vault) silently removed the first vault's schedule. Now only
/// the line for this bare repo is replaced; other vaults' lines stay.
String desktopCronCommand({
  required DesktopSchedule schedule,
  required String escapedRepo,
  required String vaultEnv,
  required String scriptPath,
}) {
  final thisRepo = "LOCALSYNC_BARE_REPO='$escapedRepo'";
  final keep = '(crontab -l 2>/dev/null | grep -vF "$thisRepo"';
  final cron = schedule.cron;
  if (cron == null) return '$keep) | crontab -';
  return '$keep; echo "$cron LOCALSYNC_BARE_REPO=\'$escapedRepo\' $vaultEnv'
      '$scriptPath >/dev/null 2>&1") | crontab -';
}
