import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/services/git_service.dart';

void main() {
  group('bareRepoPathFromSshUrl', () {
    test('extracts the path from a real localsync-format URL', () {
      expect(
          bareRepoPathFromSshUrl(
              'ssh://rapi5@172.20.10.11:22/home/rapi5/Documents/Git/localsync.git'),
          '/home/rapi5/Documents/Git/localsync.git');
    });

    test('extracts a path with a deeper nested location', () {
      expect(
          bareRepoPathFromSshUrl(
              'ssh://rapi5@172.20.10.11:22/home/rapi5/Documents/Git/pi5-obsidian/Git_bare_repo/Md_files_bare.git'),
          '/home/rapi5/Documents/Git/pi5-obsidian/Git_bare_repo/Md_files_bare.git');
    });

    test('a changed host does not change the extracted path (real-world DHCP case)',
        () {
      const path = '/home/rapi5/Documents/Git/localsync.git';
      expect(bareRepoPathFromSshUrl('ssh://rapi5@172.20.10.11:22$path'), path);
      expect(bareRepoPathFromSshUrl('ssh://rapi5@10.0.0.5:22$path'), path);
    });

    test('returns null for a non-ssh URL', () {
      expect(
          bareRepoPathFromSshUrl(
              '/home/rapi5/Documents/Git/localsync.git'),
          isNull);
    });

    test('returns null for a malformed ssh URL missing a port', () {
      expect(
          bareRepoPathFromSshUrl(
              'ssh://rapi5@172.20.10.11/home/rapi5/Documents/Git/localsync.git'),
          isNull);
    });
  });
  group('sshRepoUrl', () {
    test('relative path becomes home-relative, not glued to the port', () {
      final u = sshRepoUrl('rapi5', '172.20.10.11', 22, 'Documents/Git/LocalSync/free_1.git');
      expect(u, 'ssh://rapi5@172.20.10.11:22/~/Documents/Git/LocalSync/free_1.git');
      expect(bareRepoPathFromSshUrl(u), 'Documents/Git/LocalSync/free_1.git');
    });
    test('a broken saved address counts as the same repo (so it gets repaired)', () {
      const broken = 'ssh://rapi5@172.20.10.11:22Documents/Git/LocalSync/free_1.git';
      final fixed = sshRepoUrl('rapi5', '172.20.10.11', 22, 'Documents/Git/LocalSync/free_1.git');
      expect(bareRepoPathFromSshUrl(broken), bareRepoPathFromSshUrl(fixed));
    });
    test('absolute path unchanged', () {
      final u = sshRepoUrl('rapi5', 'h', 22, '/home/rapi5/x.git');
      expect(u, 'ssh://rapi5@h:22/home/rapi5/x.git');
      expect(bareRepoPathFromSshUrl(u), '/home/rapi5/x.git');
    });
  });
}

// 2026-09-25: "invalid url: malformed hostname" on a brand-new setup - a
// relative repo path glued straight after the port.