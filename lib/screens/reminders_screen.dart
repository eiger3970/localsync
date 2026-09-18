// screens/reminders_screen.dart
//
// 2026-09-18: real ask, live - "add a reminder settings maybe, so users
// know their reminders for widgets and notification is set by default
// to whatever you put, maybe they can change this themselves?" Round 1
// put this in Settings as a single "days" picker - real correction,
// live: "I don't fully understand your controls, as this will affect
// the Widgets and Notifications. The Widgets you had the traffic light
// settings with x y z days, the notifications and widget traffic light
// indicator are the same timers." Was two independently-chosen numbers
// for the same idea (BackupReminderService's own 3-day default vs
// LocalSyncWidget.swift's 2026-09-16 "agreed design" 1/7 thresholds) -
// this screen now controls the actual pair the widget already uses
// (amber-after/red-after), and the notification fires at the red
// threshold, not a separate one. Real ask, live - "name is Reminders,
// so it sits in the Kebab icon menu between Pull manually and
// Security" - moved out of Settings entirely, own kebab menu entry
// instead (see home_screen.dart's PopupMenuButton, value 'reminders').
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../services/backup_reminder_service.dart';
import '../services/repository_provider.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  // null until loaded - the chip rows below treat null the same as the
  // real default (1/7), since that's what both BackupReminderService and
  // LocalSyncWidget.swift's riskColor already fall back to.
  int? _amberAfterDays;
  int? _redAfterDays;

  @override
  void initState() {
    super.initState();
    final provider = context.read<RepositoryProvider>();
    provider.getAmberAfterDays().then((v) {
      if (mounted) setState(() => _amberAfterDays = v);
    });
    provider.getRedAfterDays().then((v) {
      if (mounted) setState(() => _redAfterDays = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final amber = _amberAfterDays ?? 1;
    final red = _redAfterDays ?? 7;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kVoid,
        title: Text('Reminders', style: TextStyle(color: kStar)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'One pair of timers, used in two places: the Home Screen '
              "widget's green/amber/red dot, and this notification. "
              "They're never independent settings - change either "
              'threshold here and both update together.',
              style: TextStyle(color: kTextMid, fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 24),
            _ThresholdSection(
              icon: Icons.circle,
              iconColor: Colors.amber,
              title: 'Amber after',
              subtitle: 'Widget dot turns amber once this many days pass '
                  'without a successful sync.',
              options: const {1: '1 day', 2: '2 days', 3: '3 days', 5: '5 days'},
              selected: amber,
              onSelect: (v) {
                setState(() => _amberAfterDays = v);
                context.read<RepositoryProvider>().setAmberAfterDays(v);
              },
            ),
            const SizedBox(height: 24),
            _ThresholdSection(
              icon: Icons.circle,
              iconColor: Colors.redAccent,
              title: 'Red after / reminder',
              subtitle: 'Widget dot turns red and this notification fires '
                  'once this many days pass without a successful sync. '
                  'Off turns off both.',
              options: const {0: 'Off', 3: '3 days', 7: '7 days', 14: '14 days'},
              selected: red,
              onSelect: (v) {
                setState(() => _redAfterDays = v);
                context.read<RepositoryProvider>().setRedAfterDays(v);
              },
            ),
            const SizedBox(height: 28),
            // 2026-09-18: real ask, live - "make it testable," about the
            // notification specifically (no Xcode/device-console access
            // on this user's setup to confirm the permission prompt or
            // delivery any faster than waiting the real red-threshold
            // number of days). Same scheduleReminder() a real sync
            // success already calls, just a short real delay instead -
            // a genuine notification, nothing simulated. Kept on this
            // screen (moved from the About dialog) since it's testing
            // the exact setting right above it, not a separate concern.
            TextButton(
              style: TextButton.styleFrom(
                  padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
              onPressed: () async {
                await BackupReminderService()
                    .scheduleReminder(delay: const Duration(seconds: 10));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'Test reminder scheduled - background the app now, '
                        'it should arrive in ~10 seconds.'),
                    duration: Duration(seconds: 6),
                  ),
                );
              },
              child: Text('Send test reminder',
                  style: TextStyle(color: kGreen, fontSize: 13)),
            ),
            const SizedBox(height: 12),
            Text(
              'The widget half of this is best-effort on this build - a '
              'known App Group/sideload-signing limitation (see the '
              "app's own history) can keep the widget from ever seeing "
              "these numbers even though they're written correctly. The "
              'notification above is unaffected by that and works either '
              'way.',
              style: TextStyle(color: kTextDim, fontSize: 12, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThresholdSection extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Map<int, String> options;
  final int selected;
  final ValueChanged<int> onSelect;
  const _ThresholdSection({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: iconColor, size: 12),
            const SizedBox(width: 8),
            Text(title,
                style: TextStyle(
                    color: kTextMid,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2)),
          ],
        ),
        const SizedBox(height: 6),
        Text(subtitle,
            style: TextStyle(color: kTextDim, fontSize: 12, height: 1.5)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in options.entries)
              _ReminderChip(
                label: entry.value,
                selected: entry.key == selected,
                onTap: () => onSelect(entry.key),
              ),
          ],
        ),
      ],
    );
  }
}

class _ReminderChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ReminderChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? kGreen.withValues(alpha: 0.15) : Colors.transparent,
          border: Border.all(color: selected ? kGreen : kBorder, width: 1.5),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? kGreen : kTextMid,
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
      ),
    );
  }
}
