import 'package:url_launcher/url_launcher.dart';
import '../features/linking/linking_state.dart';

/// Handles launching external iOS apps via URL schemes.
/// Working Copy and Obsidian both expose documented URL scheme APIs.
abstract class IosAppService {
  Future<StepResult> openWorkingCopyLinkURL();
  Future<StepResult> openObsidian();
  Future<StepResult> openWorkingCopy();
  Future<bool> isWorkingCopyInstalled();
  Future<bool> isObsidianInstalled();
}

class IosAppServiceImpl implements IosAppService {
  /// The vault name on-device. Configurable in settings.
  final String vaultName;

  /// The Working Copy repo name (matches bare repo name without .git).
  final String repoName;

  IosAppServiceImpl({
    required this.vaultName,
    required this.repoName,
  });

  // ─────────────────────────────────────────────
  // URL Schemes
  // ─────────────────────────────────────────────

  /// Working Copy x-callback-url for linking a local folder.
  /// Format: working-copy://x-callback-url/link?repo=NAME&path=PATH
  ///
  /// The vault path on iOS is always under:
  /// file:///private/var/mobile/Containers/Data/Application/.../On My iPhone/Obsidian/VAULT_NAME
  ///
  /// Working Copy accepts the short form: just the vault folder name
  /// relative to the Obsidian app's document directory.
  Uri get _workingCopyLinkUri => Uri.parse(
    'working-copy://x-callback-url/link'
    '?repo=${Uri.encodeComponent(repoName)}'
    '&path=${Uri.encodeComponent(vaultName)}'
    '&x-success=${Uri.encodeComponent('synclocal://link-success')}'
    '&x-error=${Uri.encodeComponent('synclocal://link-error')}',
  );

  Uri get _obsidianUri => Uri.parse('obsidian://');
  Uri get _workingCopyBaseUri => Uri.parse('working-copy://');

  // ─────────────────────────────────────────────
  // IosAppService implementation
  // ─────────────────────────────────────────────

  @override
  Future<StepResult> openWorkingCopyLinkURL() async {
    if (!await isWorkingCopyInstalled()) {
      return const StepFailure(
        error: LinkingError.workingCopyNotInstalled,
        diagnosis: LinkingError.workingCopyNotInstalled.diagnosis,
        resolution: LinkingError.workingCopyNotInstalled.resolution,
      );
    }

    try {
      // We launch and don't await the result — Working Copy takes over.
      // The outcome (success/expected-fail) is handled by step logic,
      // not by the URL callback, because step 3 expects a fail.
      await launchUrl(
        _workingCopyLinkUri,
        mode: LaunchMode.externalApplication,
      );
      return const StepSuccess(message: 'Working Copy link URL launched');
    } catch (e) {
      return StepFailure(
        error: LinkingError.unexpectedLinkError,
        diagnosis: 'URL launch failed: $e',
        resolution: LinkingError.unexpectedLinkError.resolution,
      );
    }
  }

  @override
  Future<StepResult> openObsidian() async {
    if (!await isObsidianInstalled()) {
      return const StepFailure(
        error: LinkingError.obsidianNotInstalled,
        diagnosis: LinkingError.obsidianNotInstalled.diagnosis,
        resolution: LinkingError.obsidianNotInstalled.resolution,
      );
    }

    try {
      await launchUrl(_obsidianUri, mode: LaunchMode.externalApplication);
      return const StepSuccess(message: 'Obsidian opened');
    } catch (e) {
      return StepFailure(
        error: LinkingError.obsidianNotInstalled,
        diagnosis: 'Could not open Obsidian: $e',
        resolution: LinkingError.obsidianNotInstalled.resolution,
      );
    }
  }

  @override
  Future<StepResult> openWorkingCopy() async {
    try {
      await launchUrl(_workingCopyBaseUri, mode: LaunchMode.externalApplication);
      return const StepSuccess(message: 'Working Copy opened');
    } catch (e) {
      return StepFailure(
        error: LinkingError.workingCopyNotInstalled,
        diagnosis: 'Could not open Working Copy: $e',
        resolution: LinkingError.workingCopyNotInstalled.resolution,
      );
    }
  }

  @override
  Future<bool> isWorkingCopyInstalled() async {
    return await canLaunchUrl(Uri.parse('working-copy://'));
  }

  @override
  Future<bool> isObsidianInstalled() async {
    return await canLaunchUrl(Uri.parse('obsidian://'));
  }
}
