// 2026-08-27: Tier 0 (docs/product-tiers.md) added Repository.syncMode -
// a real, persisted (shared_preferences JSON, see database_service.dart)
// field distinguishing a plain-file-sync repo from an Obsidian-vault one.
// The one thing that actually matters here is backward compatibility: an
// already-saved repo record has no 'sync_mode' key at all, and must keep
// reading as obsidianVault, not crash or silently become genericFolder.
import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/models/repository.dart';

Repository _sample({SyncMode syncMode = SyncMode.obsidianVault}) => Repository(
      name: 'Test vault',
      remoteHost: '192.168.1.1',
      remoteUser: 'rapi5',
      remotePath: '/bare/repo.git',
      localPath: '/local/path',
      obsidianVaultPath: 'On My iPhone/Obsidian/Test vault',
      syncMode: syncMode,
    );

void main() {
  group('Repository.syncMode', () {
    test('defaults to obsidianVault when not specified', () {
      expect(_sample().syncMode, SyncMode.obsidianVault);
    });

    test('round-trips through toMap/fromMap for both values', () {
      for (final mode in SyncMode.values) {
        final repo = _sample(syncMode: mode);
        final restored = Repository.fromMap(repo.toMap());
        expect(restored.syncMode, mode, reason: 'failed for $mode');
      }
    });

    test('a pre-existing record with no sync_mode key reads as obsidianVault',
        () {
      // What every repo saved before this field existed looks like on
      // disk - the exact shape fromMap must keep handling correctly.
      final legacyMap = _sample().toMap()..remove('sync_mode');
      expect(Repository.fromMap(legacyMap).syncMode, SyncMode.obsidianVault);
    });

    test('an unrecognized sync_mode value falls back to obsidianVault, not a crash',
        () {
      final corruptMap = _sample().toMap();
      corruptMap['sync_mode'] = 'somethingUnexpected';
      expect(
          Repository.fromMap(corruptMap).syncMode, SyncMode.obsidianVault);
    });

    test('copyWith can switch modes', () {
      final repo = _sample();
      final switched = repo.copyWith(syncMode: SyncMode.genericFolder);
      expect(switched.syncMode, SyncMode.genericFolder);
      expect(repo.syncMode, SyncMode.obsidianVault); // original untouched
    });
  });
}
