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
  Future<bool> isObsidianInstalled() async {
    return await canLaunchUrl(Uri.parse('obsidian://'));
  }
}
