// screens/reminders_screen.dart
//
// 2026-09-18: real ask, live - one pair of day-thresholds (amber/red),
// shared by the Home Screen widget's dot colour and these two
// notifications - not independent settings. Round 2 correction, live:
// "Your Reminder text is verbose" - trimmed hard. Round 2 also added a
// real amber notification (was red-only) and "text is to refer to sync
// with wording using backup also... Reminders are a backup reminder"
// - "backup (sync)" wording throughout, kebab label renamed to Backup
// reminder (see home_screen.dart's PopupMenuButton, value 'reminders').
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
        title: Text('Backup reminder', style: TextStyle(color: kStar)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ThresholdSection(
              icon: Icons.circle,
              iconColor: Colors.amber,
              title: 'Amber after',
              subtitle: 'Amber dot + notification.',
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
              title: 'Red after',
              subtitle: 'Red dot + notification. Off disables both.',
              options: const {0: 'Off', 3: '3 days', 7: '7 days', 14: '14 days'},
              selected: red,
              onSelect: (v) {
                setState(() => _redAfterDays = v);
                context.read<RepositoryProvider>().setRedAfterDays(v);
              },
            ),
            const SizedBox(height: 28),
            // 2026-09-18: "make it testable" - no Xcode/device-console
            // access to confirm delivery any faster than waiting the
            // real thresholds out. Same scheduleReminder() a real sync
            // success already calls, both notifications on short delays
            // instead of real days.
            TextButton(
              style: TextButton.styleFrom(
                  padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
              onPressed: () async {
                await BackupReminderService().scheduleReminder(
                  amberDelay: const Duration(seconds: 8),
                  redDelay: const Duration(seconds: 14),
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Test notifications scheduled - '
                        'background the app now, amber in ~8s, red in '
                        '~14s.'),
                    duration: Duration(seconds: 6),
                  ),
                );
              },
              child: Text('Send test notifications',
                  style: TextStyle(color: kGreen, fontSize: 13)),
            ),
            const SizedBox(height: 12),
            Text(
              "Widget colours may not update on this build - a known "
              'signing limitation. The notifications above are unaffected.',
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
