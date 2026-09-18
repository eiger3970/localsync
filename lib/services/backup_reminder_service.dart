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
import 'database_service.dart';

// 2026-09-18 (round 3): 3 -> 7 days - unified with
// LocalSyncWidget.swift's own 2026-09-16 "agreed design" red threshold
// (days >= 7) instead of being a second, independently-chosen number for
// the same idea. See database_service.dart's getRedAfterDays.
const kBackupReminderDelay = Duration(days: 7);
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
  /// one [delay] from now - called after every sync that actually
  /// succeeds, so a regularly-synced repo never fires this at all.
  ///
  /// 2026-09-18: real ask, live - "make it testable." [delay] used to be
  /// hardcoded to kBackupReminderDelay (3 real days) with no way to
  /// confirm the permission prompt or actual delivery without waiting
  /// that long. Home screen's DISCLAIMER section now has a real "Send
  /// test reminder" action that calls this with a short delay instead -
  /// same method, same real notification, nothing simulated.
  ///
  /// 2026-09-18 (round 2): real ask, live - "add a reminder settings
  /// maybe, so users know their reminders... is set by default to
  /// whatever you put, maybe they can change this themselves?" [delay]
  /// left null (every real sync-success call site does this) now reads
  /// the user's own Reminders choice instead of always falling back to
  /// the default - an explicit Duration (only the test button passes
  /// one) still overrides that lookup entirely.
  ///
  /// 2026-09-18 (round 3): real ask, live - "the notifications and
  /// widget traffic light indicator are the same timers." The stored
  /// value read here is now the RED threshold (DatabaseService.
  /// getRedAfterDays) - the same number LocalSyncWidget.swift's
  /// riskColor turns red at, not a separate reminder-only number. A
  /// stored 0 means the user turned reminders (and the red state) off,
  /// which cancels rather than schedules.
  Future<void> scheduleReminder({Duration? delay}) async {
    if (kIsWeb) return;
    try {
      await init();
      final effectiveDelay = delay ?? await _resolveStoredDelay();
      if (effectiveDelay == null) {
        await cancelReminder();
        return;
      }
      await _plugin.zonedSchedule(
        id: _reminderNotificationId,
        scheduledDate:
            tz.TZDateTime.from(DateTime.now().add(effectiveDelay), tz.UTC),
        title: 'LocalSync',
        // 2026-09-18: "a few days" was written for the old fixed 3-day
        // default - stays accurate now the delay is user-configurable
        // (could be 1 day or 14).
        body: "It's been a while since your last backup - open "
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

  Future<Duration?> _resolveStoredDelay() async {
    final days = await DatabaseService().getRedAfterDays();
    if (days == null) return kBackupReminderDelay;
    if (days <= 0) return null;
    return Duration(days: days);
  }

  Future<void> cancelReminder() async {
    if (kIsWeb) return;
    try {
      await _plugin.cancel(id: _reminderNotificationId);
    } catch (_) {}
  }
}
