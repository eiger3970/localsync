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
// Two notifications (amber + red), each rescheduled (not stacked) every
// time a sync actually succeeds. If the user keeps syncing regularly,
// both keep getting pushed back and never fire; if they stop, amber
// fires first, red fires later, at the two thresholds set in Reminders.
//
// 2026-09-18 (round 4): real ask, live - "I just want Widgets to show
// amber dot after 1 day and an amber notification sent. I want red dot
// after 7 days and a red notification sent." Was one notification, at
// the red threshold only - now genuinely two, one per threshold,
// matching the widget's own two-color state exactly.
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
import 'database_service.dart';

const kAmberReminderDelay = Duration(days: 1);
const kRedReminderDelay = Duration(days: 7);
const _amberNotificationId = 1;
const _redNotificationId = 2;

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

  /// Reschedules both notifications from now - called after every sync
  /// that actually succeeds. [amberDelay]/[redDelay] override the
  /// stored Reminders thresholds (only the test button passes these);
  /// left null, each reads its own DatabaseService value.
  Future<void> scheduleReminder({
    Duration? amberDelay,
    Duration? redDelay,
  }) async {
    if (kIsWeb) return;
    try {
      await init();
      await _scheduleOne(
        id: _amberNotificationId,
        delay: amberDelay ?? await _resolveDelay(kAmberReminderDelay,
            (db) => db.getAmberAfterDays()),
        body: 'A day since your last backup (sync) - worth a check.',
      );
      await _scheduleOne(
        id: _redNotificationId,
        delay: redDelay ?? await _resolveDelay(kRedReminderDelay,
            (db) => db.getRedAfterDays()),
        body: "It's been a while since your last backup (sync) - open "
            'LocalSync to catch up.',
      );
    } catch (_) {
      // Best-effort - a failed schedule (permission denied, simulator
      // with no real notification support, etc.) never blocks or fails
      // the sync itself.
    }
  }

  Future<void> _scheduleOne({
    required int id,
    required Duration? delay,
    required String body,
  }) async {
    if (delay == null) {
      await _plugin.cancel(id: id);
      return;
    }
    await _plugin.zonedSchedule(
      id: id,
      scheduledDate: tz.TZDateTime.from(DateTime.now().add(delay), tz.UTC),
      title: 'LocalSync',
      body: body,
      notificationDetails: const NotificationDetails(
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  /// null stored days = use [fallback]; 0 = off (null delay, cancels);
  /// otherwise Duration(days: stored).
  Future<Duration?> _resolveDelay(
    Duration fallback,
    Future<int?> Function(DatabaseService) getDays,
  ) async {
    final days = await getDays(DatabaseService());
    if (days == null) return fallback;
    if (days <= 0) return null;
    return Duration(days: days);
  }

  Future<void> cancelReminder() async {
    if (kIsWeb) return;
    try {
      await _plugin.cancel(id: _amberNotificationId);
      await _plugin.cancel(id: _redNotificationId);
    } catch (_) {}
  }
}
