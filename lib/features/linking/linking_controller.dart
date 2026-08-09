// features/linking/linking_controller.dart
//
// Drives the vault setup sequence. Rewritten 2026-08-08 for the git2dart
// architecture (see lib/STRUCTURE.md) - the clone happens in-process now,
// no more Working Copy URL-scheme launches or multi-step link/retry dance.
// Only one park point remains: the user opening Obsidian and pointing it
// at Synclocal's already-populated folder.
//
// Resumes on AppLifecycleState.resumed via lifecycle_observer.dart.

import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../services/git_service.dart';
import '../../services/ios_app_service.dart';
import '../../services/ssh_key_paths.dart';
import 'linking_state.dart';

class LinkingController extends ChangeNotifier {
  final String desktopUser;
  final String desktopIp;
  final String bareRepoPath;
  final String localVaultPath; // Synclocal's own Documents dir
  final int    sshPort;

  final IosAppService _iosApps;

  LinkingController({
    required this.desktopUser,
    required this.desktopIp,
    required this.bareRepoPath,
    required this.localVaultPath,
    this.sshPort = 22,
    IosAppService? iosApps,
  }) : _iosApps = iosApps ?? IosAppServiceImpl();

  LinkingStep  _step        = LinkingStep.idle;
  StepFailure? _lastFailure;
  bool         _isRunning   = false;

  LinkingStep  get step        => _step;
  StepFailure? get lastFailure => _lastFailure;
  bool         get isRunning   => _isRunning;

  double get progress => switch (_step) {
    LinkingStep.idle                       => 0.0,
    LinkingStep.checkingPairing            => 0.10,
    LinkingStep.cloning                    => 0.50,
    LinkingStep.awaitingObsidianVaultOpen  => 0.80,
    LinkingStep.verifySync                 => 0.95,
    LinkingStep.complete                   => 1.0,
    LinkingStep.failed                     => 0.0,
  };

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<void> startLinking() async {
    assert(_step == LinkingStep.idle || _step == LinkingStep.failed);
    _reset();
    _isRunning = true;
    notifyListeners();
    await _checkPairing();
  }

  Future<void> resumeFromBackground() async {
    if (!_isRunning) return;
    if (_step == LinkingStep.awaitingObsidianVaultOpen) {
      await _verifySync();
    }
  }

  Future<void> confirmParkedActionComplete() async {
    await resumeFromBackground();
  }

  void reset() { _reset(); notifyListeners(); }

  // ── Steps ──────────────────────────────────────────────────────────────────

  Future<void> _checkPairing() async {
    _step = LinkingStep.checkingPairing;
    notifyListeners();

    final privateKeyPath = await SshKeyPaths.privateKeyPath();
    final publicKeyPath  = await SshKeyPaths.publicKeyPath();

    if (!kIsWeb) {
      final hasKeypair = await _keypairExists(privateKeyPath, publicKeyPath);
      if (!hasKeypair) {
        return _fail(const StepFailure(LinkingError.pairingNotComplete));
      }
    }

    await _clone(privateKeyPath, publicKeyPath);
  }

  Future<void> _clone(String privateKeyPath, String publicKeyPath) async {
    _step = LinkingStep.cloning;
    notifyListeners();

    if (!kIsWeb) {
      final git = GitServiceImpl(
        bareRepoPath: bareRepoPath,
        localVaultPath: localVaultPath,
        sshHost: desktopIp,
        sshUser: desktopUser,
        sshPrivateKeyPath: privateKeyPath,
        sshPublicKeyPath: publicKeyPath,
        sshPort: sshPort,
      );
      final result = await git.pullFromBareRepo(); // clones if not present yet
      if (result case StepFailure()) {
        return _fail(result);
      }
    }

    await _openObsidianForVaultPick();
  }

  Future<void> _openObsidianForVaultPick() async {
    // Fixed 2026-08-09: this used to call _iosApps.openObsidian() (which
    // launches Obsidian immediately, backgrounding Synclocal) BEFORE
    // setting the step/calling notifyListeners() - meaning the "here's
    // what to do in Obsidian" instructions never got a chance to render
    // before the app switch happened. Confirmed on a real device: user
    // was dropped straight into Obsidian with no on-screen guidance and
    // had to guess. Now shows instructions first and waits for a
    // deliberate tap (openObsidianNow) before actually launching.
    if (!kIsWeb) {
      final installed = await _iosApps.isObsidianInstalled();
      if (!installed) {
        return _fail(const StepFailure(LinkingError.obsidianNotInstalled));
      }
    }

    _step = LinkingStep.awaitingObsidianVaultOpen;
    notifyListeners();
  }

  Future<void> openObsidianNow() async {
    if (kIsWeb) return;
    final result = await _iosApps.openObsidian();
    if (result case StepFailure()) {
      _fail(result);
    }
  }

  Future<void> _verifySync() async {
    _step = LinkingStep.verifySync;
    notifyListeners();

    // Fixed 2026-08-09: this was a no-op that unconditionally reported
    // success regardless of what actually happened - confirmed on a
    // real device, user did nothing in Obsidian, switched straight back,
    // and the app still said "You're all set!" The one thing Synclocal
    // can genuinely check from its own sandbox is whether the download
    // actually produced real files - it cannot see into Obsidian to
    // confirm the folder was opened as a vault there (no cross-app
    // introspection on iOS). Being honest about that limit rather than
    // pretending to verify something unverifiable.
    if (!kIsWeb) {
      final gitDirExists = await Directory('$localVaultPath/.git').exists();
      final isEmpty = await Directory(localVaultPath).list().isEmpty;
      if (!gitDirExists || isEmpty) {
        return _fail(const StepFailure(LinkingError.cloneVerificationFailed));
      }
    }

    _step = LinkingStep.complete;
    _isRunning = false;
    notifyListeners();
  }

  // ── UI strings ─────────────────────────────────────────────────────────────

  String? get currentInstruction => switch (_step) {
    // Cut down from an earlier 6-step version after real device testing
    // (2026-08-09): the whole instruction card disappears the instant
    // OPEN OBSIDIAN is tapped (Synclocal gets backgrounded), so a first-
    // time user has no way to refer back to steps 2-6 while actually
    // inside Obsidian. Only one fact genuinely needs to be remembered -
    // which folder to pick. Everything else (tapping the button,
    // switching back, tapping Continue) is self-evident from the UI
    // itself when they get there.
    LinkingStep.awaitingObsidianVaultOpen =>
      'Your notes have arrived on this phone.\n\n'
      'Next, tell Obsidian where to find them:\n'
      'Tap OPEN OBSIDIAN, then in Obsidian:\n'
      'Open folder as vault → On My iPhone → Synclocal\n\n'
      'Come back here when you\'re done.',

    _ => null,
  };

  String get stepLabel => switch (_step) {
    LinkingStep.checkingPairing => 'Checking setup…',
    LinkingStep.cloning         => 'Downloading your notes…',
    LinkingStep.verifySync      => 'Verifying…',
    _                           => 'Working…',
  };

  String get stepSubtitle => switch (_step) {
    LinkingStep.cloning => 'Connecting via SSH and copying your vault',
    _                   => 'iOS is processing — this is not frozen',
  };

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<bool> _keypairExists(String privatePath, String publicPath) async {
    final f1 = await _fileExists(privatePath);
    final f2 = await _fileExists(publicPath);
    return f1 && f2;
  }

  Future<bool> _fileExists(String path) async {
    try {
      return await File(path).exists();
    } catch (_) {
      return false;
    }
  }

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
