// services/backup_reminder_service.dart
//
// 2026-09-18: real ask, live - "Sync timer for widgets and phone
// notification to remind when last backed up." Scoped down to just the
// notification half (the widget's own "last synced" surface already
// exists but is broken under free/sideload signing - see
// project_synclocal_app memory's 2026-09-17 diagnosis - fixing that is
// a separate, unrelated problem). User's own choice when asked: trigger
// on real time-since-last-sync, not a fixed daily nudge.
//
// One notification, rescheduled (not stacked) every time a sync
// actually succeeds - RepositoryProvider calls scheduleReminder() after
// every successful pull/push/desktop-sync-triggered-pull, which cancels
// whatever was already pending and schedules a fresh one
// kReminderDelay out. If the user keeps syncing regularly, the
// reminder keeps getting pushed back and never fires; if they stop,
// it fires once, kReminderDelay after their last real sync.
//
// UTC-based scheduling (TZDateTime.from(..., tz.UTC)), not the
// device's real local timezone - this is a "remind me after N days
// of silence" reminder, not a "remind me at 9am local time" alarm, so
// the extra flutter_timezone dependency needed for a real IANA
// timezone name isn't worth adding just for this.
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

const kBackupReminderDelay = Duration(days: 3);
const _reminderNotificationId = 1;

class BackupReminderService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized || kIsWeb) return;
    tz_data.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    // Requested explicitly (not via the initialize() flags above) so
    // the OS permission prompt fires right when this service starts,
    // not silently skipped - matches every other real permission this
    // app requests (App Tracking Transparency, notifications) rather
    // than assuming the flags alone are enough on every iOS version.
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    _initialized = true;
  }

  /// Cancels whatever reminder was already pending and schedules a new
  /// one [kBackupReminderDelay] from now - called after every sync that
  /// actually succeeds, so a regularly-synced repo never fires this at
  /// all.
  Future<void> scheduleReminder() async {
    if (kIsWeb) return;
    try {
      await init();
      await _plugin.zonedSchedule(
        id: _reminderNotificationId,
        scheduledDate:
            tz.TZDateTime.from(DateTime.now().add(kBackupReminderDelay), tz.UTC),
        title: 'LocalSync',
        body: "It's been a few days since your last backup - open "
            'LocalSync to catch up.',
        notificationDetails: const NotificationDetails(
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } catch (_) {
      // Best-effort - a failed schedule (permission denied, simulator
      // with no real notification support, etc.) never blocks or fails
      // the sync itself.
    }
  }

  Future<void> cancelReminder() async {
    if (kIsWeb) return;
    try {
      await _plugin.cancel(id: _reminderNotificationId);
    } catch (_) {}
  }
}
