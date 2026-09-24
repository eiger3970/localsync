// services/files_app_path.dart
//
// 2026-09-24: real ask, live - "Can't you show the full path, so Phone
// -> Files app -> On My iPhone -> Obsidian_phone_vault/LocalSync/Vault
// Backup <date and time>." The picker hands back iOS's internal path
// (/private/var/mobile/Containers/...), which means nothing to a person.
// This turns it into the taps they'd actually make in the Files app,
// starting from the top every time.
//
// Three real shapes:
//  - iCloud:   .../Mobile Documents/iCloud~md~obsidian/Documents/<vault>
//              -> iCloud Drive > Obsidian > <vault>
//  - a File Provider folder (another app's "On My iPhone" folder):
//              .../File Provider Storage/<a>/<b>
//              -> On My iPhone > <a> > <b>
//  - an app's own Documents (Obsidian's local vaults live here):
//              .../Containers/Data/Application/<id>/Documents/<vault>
//              -> On My iPhone > Obsidian > <vault>
//    The path itself doesn't name the app - LocalSync only links
//    Obsidian vaults, so "Obsidian" is the honest label there.
// Anything else falls back to the folder's own name under On My iPhone.

/// The Files app route to [absolutePath], top first - e.g.
/// ['On My iPhone', 'Obsidian', 'Obsidian_phone_vault'].
List<String> filesAppRoute(String absolutePath) {
  final parts =
      absolutePath.split('/').where((p) => p.isNotEmpty).toList();

  final mobileDocs = parts.indexOf('Mobile Documents');
  if (mobileDocs != -1 && mobileDocs + 1 < parts.length) {
    final container = parts[mobileDocs + 1];
    var rest = parts.sublist(mobileDocs + 2);
    if (rest.isNotEmpty && rest.first == 'Documents') rest = rest.sublist(1);
    final app = container == 'com~apple~CloudDocs'
        ? <String>[]
        : [container.contains('obsidian') ? 'Obsidian' : container.split('~').last];
    return ['iCloud Drive', ...app, ...rest];
  }

  final provider = parts.indexOf('File Provider Storage');
  if (provider != -1) {
    return ['On My iPhone', ...parts.sublist(provider + 1)];
  }

  final app = parts.indexOf('Application');
  if (app != -1 && app + 2 < parts.length && parts[app + 2] == 'Documents') {
    return ['On My iPhone', 'Obsidian', ...parts.sublist(app + 3)];
  }

  return ['On My iPhone', if (parts.isNotEmpty) parts.last];
}

/// [filesAppRoute] plus [extra] vault-relative segments, as one line
/// from the very top: "Home Screen > Files app (blue folder icon) > On
/// My iPhone > Obsidian > vault > LocalSync > ...". Starts at the Home
/// Screen, and names the icon, because - real feedback, same day - "new
/// users sometimes have no clue about a Files app... they're coming
/// from cloud use."
String filesAppRouteText(String absolutePath, [String extra = '']) {
  final route = [
    'Phone home screen',
    'Files app (blue folder icon)',
    ...filesAppRoute(absolutePath),
    ...extra.split('/').where((p) => p.isNotEmpty),
  ];
  return route.join(' -> ');
}

/// Opens the Files app straight at [absolutePath] (iOS "shareddocuments"
/// scheme) - so nobody has to find the folder by hand at all.
Uri filesAppUri(String absolutePath) =>
    Uri.parse('shareddocuments://${Uri.encodeFull(absolutePath)}');
