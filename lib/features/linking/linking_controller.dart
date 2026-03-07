// features/linking/linking_controller.dart
//
// Drives the Fresh Setup linking sequence (SSOT steps 11–15).
// Desktop vault exists. Phone gets a copy.
//
// Parks at steps requiring user action in external apps.
// Resumes on AppLifecycleState.resumed via lifecycle_observer.dart.

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'linking_state.dart';

class LinkingController extends ChangeNotifier {
  final String desktopUser;
  final String desktopIp;
  final String bareRepoPath;
  final String vaultName;
  final String repoName;
  final int    sshPort;

  LinkingController({
    required this.desktopUser,
    required this.desktopIp,
    required this.bareRepoPath,
    required this.vaultName,
    required this.repoName,
    this.sshPort = 22,
  });

  LinkingStep  _step        = LinkingStep.idle;
  StepFailure? _lastFailure;
  bool         _isRunning   = false;

  LinkingStep  get step        => _step;
  StepFailure? get lastFailure => _lastFailure;
  bool         get isRunning   => _isRunning;

  double get progress => switch (_step) {
    LinkingStep.idle                        => 0.0,
    LinkingStep.obsidianCreateVault         => 0.10,
    LinkingStep.awaitingObsidianForceClose  => 0.20,
    LinkingStep.workingCopyClone            => 0.35,
    LinkingStep.workingCopyLink             => 0.50,
    LinkingStep.awaitingObsidianIndex       => 0.55,
    LinkingStep.workingCopyLinkRetry        => 0.65,
    LinkingStep.awaitingWorkingCopyRelaunch => 0.75,
    LinkingStep.workingCopyPull             => 0.85,
    LinkingStep.verifySync                  => 0.95,
    LinkingStep.complete                    => 1.0,
    LinkingStep.failed                      => 0.0,
  };

  String get sshUrl => 'ssh://$desktopUser@$desktopIp$bareRepoPath';

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<void> startLinking() async {
    assert(_step == LinkingStep.idle || _step == LinkingStep.failed);
    _reset();
    _isRunning = true;
    notifyListeners();
    await _step11a_OpenObsidianToCreateVault();
  }

  Future<void> resumeFromBackground() async {
    if (!_isRunning) return;
    switch (_step) {
      case LinkingStep.awaitingObsidianForceClose:
        await _step12_CloneBareRepo();
      case LinkingStep.awaitingObsidianIndex:
        await _step13c_RetryLink();
      case LinkingStep.awaitingWorkingCopyRelaunch:
        await _step14_Pull();
      default:
        break;
    }
  }

  Future<void> confirmParkedActionComplete() async {
    await resumeFromBackground();
  }

  void reset() { _reset(); notifyListeners(); }

  // ── Steps 11–15 ────────────────────────────────────────────────────────────

  Future<void> _step11a_OpenObsidianToCreateVault() async {
    _step = LinkingStep.obsidianCreateVault;
    notifyListeners();

    if (!kIsWeb) {
      final ok = await canLaunchUrl(Uri.parse('obsidian://'));
      if (!ok) return _fail(const StepFailure(LinkingError.obsidianNotInstalled));
      await launchUrl(Uri.parse('obsidian://'), mode: LaunchMode.externalApplication);
    }

    _step = LinkingStep.awaitingObsidianForceClose;
    notifyListeners();
  }

  Future<void> _step12_CloneBareRepo() async {
    _step = LinkingStep.workingCopyClone;
    notifyListeners();

    if (!kIsWeb) {
      final ok = await canLaunchUrl(Uri.parse('working-copy://'));
      if (!ok) return _fail(const StepFailure(LinkingError.workingCopyNotInstalled));
      final uri = Uri.parse(
        'working-copy://x-callback-url/clone'
        '?remote=${Uri.encodeComponent(sshUrl)}'
        '&x-success=${Uri.encodeComponent('synclocal://clone-success')}'
        '&x-error=${Uri.encodeComponent('synclocal://clone-error')}',
      );
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    _step = LinkingStep.workingCopyLink;
    notifyListeners();
    await _step13a_LinkToVault();
  }

  Future<void> _step13a_LinkToVault() async {
    _step = LinkingStep.workingCopyLink;
    notifyListeners();

    if (!kIsWeb) {
      final uri = Uri.parse(
        'working-copy://x-callback-url/link'
        '?repo=${Uri.encodeComponent(repoName)}'
        '&path=${Uri.encodeComponent(vaultName)}'
        '&x-success=${Uri.encodeComponent('synclocal://link-success')}'
        '&x-error=${Uri.encodeComponent('synclocal://link-error')}',
      );
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    _step = LinkingStep.awaitingObsidianIndex;
    notifyListeners();
  }

  Future<void> _step13c_RetryLink() async {
    _step = LinkingStep.workingCopyLinkRetry;
    notifyListeners();

    if (!kIsWeb) {
      final uri = Uri.parse(
        'working-copy://x-callback-url/link'
        '?repo=${Uri.encodeComponent(repoName)}'
        '&path=${Uri.encodeComponent(vaultName)}'
        '&x-success=${Uri.encodeComponent('synclocal://link-success')}'
        '&x-error=${Uri.encodeComponent('synclocal://link-error')}',
      );
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    _step = LinkingStep.awaitingWorkingCopyRelaunch;
    notifyListeners();
  }

  Future<void> _step14_Pull() async {
    _step = LinkingStep.workingCopyPull;
    notifyListeners();

    if (!kIsWeb) {
      final uri = Uri.parse(
        'working-copy://x-callback-url/pull'
        '?repo=${Uri.encodeComponent(repoName)}'
        '&x-success=${Uri.encodeComponent('synclocal://pull-success')}'
        '&x-error=${Uri.encodeComponent('synclocal://pull-error')}',
      );
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    await _step15_VerifySync();
  }

  Future<void> _step15_VerifySync() async {
    _step = LinkingStep.verifySync;
    notifyListeners();
    _step = LinkingStep.complete;
    _isRunning = false;
    notifyListeners();
  }

  // ── UI strings ─────────────────────────────────────────────────────────────

  String? get currentInstruction => switch (_step) {
    LinkingStep.awaitingObsidianForceClose =>
      'In Obsidian:\n\n'
      '→ Tap Create a vault\n'
      '→ Tap Continue without sync\n'
      '→ Type exactly: $vaultName\n'
      '→ Tap Create a vault\n\n'
      'Then force-close Obsidian\n'
      '(swipe it away in the app switcher)\n\n'
      'Then tap Continue below',

    LinkingStep.awaitingObsidianIndex =>
      'In Obsidian:\n\n'
      '→ Force-close Obsidian now\n'
      '   (swipe it away)\n'
      '→ Reopen Obsidian\n'
      '→ Tap "Trust author and enable plugins"\n'
      '→ Wait for the spinner to finish\n'
      '   (bottom-left of Obsidian)\n'
      '→ Force-close Obsidian again\n\n'
      'Then tap Continue below',

    LinkingStep.awaitingWorkingCopyRelaunch =>
      'Almost done.\n\n'
      '→ Force-close Working Copy\n'
      '   (swipe it away)\n'
      '→ Reopen Working Copy\n'
      '→ The error banner will be gone\n\n'
      'Then tap Continue below',

    _ => null,
  };

  String get stepLabel => switch (_step) {
    LinkingStep.obsidianCreateVault   => 'Opening Obsidian…',
    LinkingStep.workingCopyClone      => 'Connecting to desktop…',
    LinkingStep.workingCopyLink       => 'Linking vault…',
    LinkingStep.workingCopyLinkRetry  => 'Linking vault…',
    LinkingStep.workingCopyPull       => 'Pulling your notes…',
    LinkingStep.verifySync            => 'Verifying sync…',
    _                                 => 'Working…',
  };

  String get stepSubtitle => switch (_step) {
    LinkingStep.workingCopyClone =>
      'Connecting via SSH — accept the host key when Working Copy asks',
    LinkingStep.workingCopyLink =>
      'First attempt may fail — that is normal and expected',
    LinkingStep.workingCopyPull =>
      'Downloading your notes from the desktop',
    _ => 'iOS is processing — this is not frozen',
  };

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _fail(StepFailure failure) {
    _lastFailure = failure;
    _step        = LinkingStep.failed;
    _isRunning   = false;
    notifyListeners();
  }

  void _reset() {
    _step        = LinkingStep.idle;
    _lastFailure = null;
    _isRunning   = false;
  }
}
