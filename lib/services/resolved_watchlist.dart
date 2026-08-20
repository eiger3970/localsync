// services/resolved_watchlist.dart
//
// 2026-08-20: real device finding (2026-08-19, see conflict_scanner.dart's
// resolveConflict comment) - a conflict resolved via the picker was later
// found reverted back to its exact pre-resolution content, with zero
// indication anything had happened. The coordinatedWrite fix addresses the
// most likely cause (Obsidian's own cache clobbering the write) but is
// unconfirmed on device - the presenter-registration theory isn't
// inspectable from outside Obsidian's own code.
//
// This is the safety net for if that fix doesn't hold: nothing is ever
// actually lost on a revert (the file just goes back to having the same
// SYNC CONFLICT block, which scanForConflicts already re-detects on its own
// - the underlying scan is stateless and content-based), but there's no
// reason to make the user stumble onto that by accident days later. A
// resolved entry's non-"yours" version signatures (who/when - a real
// device name + a real timestamp, never coincidentally reused) get
// remembered for a short window; if the exact same signature reappears in
// a later scan of the same file, that's the revert, flagged explicitly
// instead of just showing up as an unremarkable new conflict.

import 'conflict_scanner.dart';

class ResolvedRecord {
  final String filePath;
  final String who;
  final String? when;
  final DateTime resolvedAt;
  const ResolvedRecord({
    required this.filePath,
    required this.who,
    this.when,
    required this.resolvedAt,
  });

  Map<String, dynamic> toJson() => {
        'filePath': filePath,
        'who': who,
        'when': when,
        'resolvedAt': resolvedAt.toIso8601String(),
      };

  factory ResolvedRecord.fromJson(Map<String, dynamic> json) => ResolvedRecord(
        filePath: json['filePath'] as String,
        who: json['who'] as String,
        when: json['when'] as String?,
        resolvedAt: DateTime.parse(json['resolvedAt'] as String),
      );
}

/// One [ResolvedRecord] per non-"yours" version in [entry] - a revert
/// restores the whole conflict block, so every other side's signature is
/// worth watching for, not just the most recent one.
List<ResolvedRecord> recordsFor(ConflictEntry entry, DateTime resolvedAt) => [
      for (final v in entry.versions.skip(1))
        ResolvedRecord(
          filePath: entry.filePath,
          who: v.who,
          when: v.when,
          resolvedAt: resolvedAt,
        ),
    ];

/// Which [watchlist] entries reappear in [freshScan] - i.e. resolved, then
/// reverted. Matches on filePath + who + when: a real device name paired
/// with a real timestamp is never coincidentally reused by an unrelated
/// future conflict, so this doesn't false-positive on ordinary new
/// conflicts in the same file.
List<ResolvedRecord> findReverted(
  List<ConflictEntry> freshScan,
  List<ResolvedRecord> watchlist,
) {
  return watchlist.where((r) {
    return freshScan.any((e) =>
        e.filePath == r.filePath &&
        e.versions.any((v) => v.who == r.who && v.when == r.when));
  }).toList();
}

/// Self-cleaning: don't let the persisted list grow forever, and don't
/// keep flagging something as "recently resolved" indefinitely.
List<ResolvedRecord> pruneOld(
  List<ResolvedRecord> watchlist,
  DateTime now, {
  Duration maxAge = const Duration(days: 7),
}) {
  return watchlist
      .where((r) => now.difference(r.resolvedAt) < maxAge)
      .toList();
}
