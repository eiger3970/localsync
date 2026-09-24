import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/services/files_app_path.dart';

void main() {
  test('Obsidian local vault (app Documents) -> On My iPhone > Obsidian', () {
    expect(
        filesAppRoute('/private/var/mobile/Containers/Data/Application/'
            'ABC-123/Documents/Obsidian_phone_vault'),
        ['On My iPhone', 'Obsidian', 'Obsidian_phone_vault']);
  });
  test('parent folder (the wrong pick) -> On My iPhone > Obsidian', () {
    expect(
        filesAppRoute(
            '/private/var/mobile/Containers/Data/Application/ABC-123/Documents'),
        ['On My iPhone', 'Obsidian']);
  });
  test('iCloud Obsidian vault -> iCloud Drive > Obsidian', () {
    expect(
        filesAppRoute('/private/var/mobile/Library/Mobile Documents/'
            'iCloud~md~obsidian/Documents/My vault'),
        ['iCloud Drive', 'Obsidian', 'My vault']);
  });
  test('File Provider folder -> On My iPhone > folders', () {
    expect(
        filesAppRoute('/private/var/mobile/Containers/Shared/AppGroup/X/'
            'File Provider Storage/Notes/Vault'),
        ['On My iPhone', 'Notes', 'Vault']);
  });
  test('route text starts at the Home Screen and adds the backup path', () {
    expect(
        filesAppRouteText(
            '/private/var/mobile/Containers/Data/Application/A/Documents/V',
            'LocalSync/Vault Backup 202609241415'),
        'Home Screen > Files app (blue folder icon) > On My iPhone > '
        'Obsidian > V > LocalSync > Vault Backup 202609241415');
  });
}
