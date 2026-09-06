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
}
