import 'package:url_launcher/url_launcher.dart';
import '../features/linking/linking_state.dart';

/// Handles launching external iOS apps via URL schemes.
/// Only Obsidian, now that git operations happen in-process via git2dart
/// instead of delegating to Working Copy - see lib/STRUCTURE.md.
abstract class IosAppService {
  Future<StepResult> openObsidian();
  Future<bool> isObsidianInstalled();
}

class IosAppServiceImpl implements IosAppService {
  Uri get _obsidianUri => Uri.parse('obsidian://');

  @override
  Future<StepResult> openObsidian() async {
    if (!await isObsidianInstalled()) {
      return const StepFailure(LinkingError.obsidianNotInstalled);
    }

    try {
      await launchUrl(_obsidianUri, mode: LaunchMode.externalApplication);
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
