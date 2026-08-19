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
      final uri = Uri(
        scheme: 'obsidian',
        host: 'open',
        queryParameters: {'vault': vaultName, 'file': vaultRelativePath},
      );
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
