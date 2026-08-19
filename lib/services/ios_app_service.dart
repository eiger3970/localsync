import 'package:url_launcher/url_launcher.dart';
import '../features/linking/linking_state.dart';

/// Handles launching external iOS apps via URL schemes.
/// Only Obsidian, now that git operations happen in-process via git2dart
/// instead of delegating to Working Copy - see lib/STRUCTURE.md.
abstract class IosAppService {
  /// Opens Obsidian. When [vaultName] is given, deep-links straight to
  /// that vault (obsidian://open?vault=NAME) instead of whatever vault
  /// Obsidian last had active.
  Future<StepResult> openObsidian({String? vaultName});

  /// 2026-08-19: real user feedback, live - told to go find "LocalSync
  /// Conflict Backups" in Obsidian's own file list by hand: "humans
  /// don't need to know petty shite, that's for computer machines to
  /// deal with." The app already knows exactly which backup note it
  /// just wrote (see conflict_scanner.dart's resolveConflict) - this
  /// opens that specific note directly instead of describing a folder
  /// to go find. [vaultRelativePath] is the note's path from the vault
  /// root, e.g. "LocalSync Conflict Backups/note - 202608191945.md".
  Future<StepResult> openObsidianFile(
      {required String vaultName, required String vaultRelativePath});

  Future<bool> isObsidianInstalled();
}

class IosAppServiceImpl implements IosAppService {
  Uri _obsidianUri({String? vaultName}) => (vaultName == null || vaultName.isEmpty)
      ? Uri.parse('obsidian://')
      : Uri(scheme: 'obsidian', host: 'open', queryParameters: {'vault': vaultName});

  @override
  Future<StepResult> openObsidian({String? vaultName}) async {
    if (!await isObsidianInstalled()) {
      return const StepFailure(LinkingError.obsidianNotInstalled);
    }

    try {
      await launchUrl(_obsidianUri(vaultName: vaultName),
          mode: LaunchMode.externalApplication);
      return const StepSuccess(message: 'Obsidian opened');
    } catch (e) {
      return const StepFailure(LinkingError.obsidianNotInstalled);
    }
  }

  @override
  Future<StepResult> openObsidianFile(
      {required String vaultName, required String vaultRelativePath}) async {
    if (!await isObsidianInstalled()) {
      return const StepFailure(LinkingError.obsidianNotInstalled);
    }
    try {
      // 2026-08-19: real device bug - Dart's Uri(queryParameters: {...})
      // percent-encodes every character in a value that isn't "query
      // component safe", including `/` (-> %2F). Obsidian's own file
      // parameter expects literal `/` between folder segments, each
      // segment individually encoded (spaces etc.) - not the whole
      // path double-encoded as one opaque blob. With the wrong
      // encoding, Obsidian silently failed to resolve the file and
      // just opened whatever note it already had active, with no error
      // surfaced anywhere - confirmed on device, opened a 3-hour-old
      // unrelated note instead of the one just backed up.
      final encodedFile =
          vaultRelativePath.split('/').map(Uri.encodeComponent).join('/');
      final uri = Uri.parse(
          'obsidian://open?vault=${Uri.encodeComponent(vaultName)}&file=$encodedFile');
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return const StepSuccess(message: 'Backup note opened');
    } catch (e) {
      return const StepFailure(LinkingError.obsidianNotInstalled);
    }
  }

  @override
  Future<bool> isObsidianInstalled() async {
    return await canLaunchUrl(Uri.parse('obsidian://'));
  }
}
