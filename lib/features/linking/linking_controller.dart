// features/linking/linking_controller.dart
//
// Drives the vault setup sequence.
//
// Rewritten 2026-08-09 with the flow direction corrected - see
// linking_state.dart's header comment and lib/STRUCTURE.md for the full
// finding. Obsidian creates and owns its vault folder first; Synclocal
// requests access to it afterward via iOS's real folder picker
// (VaultFolderService), obtaining a security-scoped bookmark. The
// clone happens into that externally-owned folder, not Synclocal's own
// private Documents directory.
//
// Resumes on AppLifecycleState.resumed via lifecycle_observer.dart.

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../services/git_service.dart';
import '../../services/ios_app_service.dart';
import '../../services/ssh_key_paths.dart';
import '../../services/vault_folder_service.dart';
import '../../constants.dart';
import 'linking_state.dart';

class LinkingController extends ChangeNotifier {
  final String desktopUser;
  final String desktopIp;
  final String bareRepoPath;
  final int    sshPort;

  final IosAppService _iosApps;
  final VaultFolderService _vaultFolder;

  LinkingController({
    required this.desktopUser,
    required this.desktopIp,
    required this.bareRepoPath,
    this.sshPort = 22,
    IosAppService? iosApps,
    VaultFolderService? vaultFolder,
  }) : _iosApps     = iosApps ?? IosAppServiceImpl(),
       _vaultFolder = vaultFolder ?? VaultFolderService();

  LinkingStep  _step        = LinkingStep.idle;
  StepFailure? _lastFailure;
  bool         _isRunning   = false;

  // Held between _checkPairing() and _cloneInto() - the flow now pauses
  // for real user interaction (create vault, pick folder) in between,
  // so these can no longer just be call-chain parameters.
  String? _privateKeyPath;
  String? _publicKeyPath;

  // Set once the user picks their vault folder - exposed so
  // linking_screen.dart can persist them into a Repository record on
  // completion.
  String? _pickedVaultPath;
  String? _pickedVaultBookmark;

  LinkingStep  get step               => _step;
  StepFailure? get lastFailure        => _lastFailure;
  bool         get isRunning          => _isRunning;
  String?      get pickedVaultPath    => _pickedVaultPath;
  String?      get pickedVaultBookmark => _pickedVaultBookmark;

  double get progress => switch (_step) {
    LinkingStep.idle                  => 0.0,
    LinkingStep.checkingPairing       => 0.10,
    LinkingStep.awaitingVaultCreation => 0.30,
    LinkingStep.pickingVaultFolder    => 0.55,
    LinkingStep.cloning               => 0.80,
    LinkingStep.verifySync            => 0.95,
    LinkingStep.complete              => 1.0,
    LinkingStep.failed                => 0.0,
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
    // Only meaningful pause-point left is awaitingVaultCreation (after
    // tapping OPEN OBSIDIAN to create the vault). pickingVaultFolder
    // isn't a background-pause step - the native picker result comes
    // back directly through the method channel, awaited in Dart, not
    // via app-resume detection.
  }

  Future<void> openObsidianNow() async {
    if (kIsWeb) return;
    final result = await _iosApps.openObsidian();
    if (result case StepFailure()) {
      _fail(result);
    }
  }

  /// Called when the user confirms they've created the vault in
  /// Obsidian (button tap on the awaitingVaultCreation screen).
  Future<void> confirmVaultCreated() async {
    if (_step != LinkingStep.awaitingVaultCreation) return;
    _step = LinkingStep.pickingVaultFolder;
    notifyListeners();
  }

  /// Called when the user taps "Select vault folder" - presents the
  /// native folder picker.
  Future<void> pickVaultFolder() async {
    if (_step != LinkingStep.pickingVaultFolder) return;

    if (kIsWeb) {
      await _cloneInto('/web-stub-vault', '');
      return;
    }

    VaultFolderResult? result;
    try {
      result = await _vaultFolder.pickFolder();
    } on PlatformException catch (e) {
      // Fixed 2026-08-09: real device confirmed tapping this button did
      // nothing at all - a genuine native-side failure (the channel not
      // registered, no root view controller to present from) was being
      // silently dropped instead of shown. Now surfaces as a real,
      // visible failure with the raw platform error attached.
      return _fail(StepFailure(
        LinkingError.vaultPickerFailed,
        debugDetail: '${e.code}: ${e.message}',
      ));
    }
    if (result == null) {
      // User cancelled the picker - stay on this step, let them retry.
      notifyListeners();
      return;
    }
    await _cloneInto(result.path, result.bookmark);
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

    _privateKeyPath = privateKeyPath;
    _publicKeyPath  = publicKeyPath;
    await _awaitVaultCreation();
  }

  Future<void> _awaitVaultCreation() async {
    if (!kIsWeb) {
      final installed = await _iosApps.isObsidianInstalled();
      if (!installed) {
        return _fail(const StepFailure(LinkingError.obsidianNotInstalled));
      }
    }

    _step = LinkingStep.awaitingVaultCreation;
    notifyListeners();
  }

  Future<void> _cloneInto(String path, String bookmark) async {
    _pickedVaultPath     = path;
    _pickedVaultBookmark = bookmark;
    _step = LinkingStep.cloning;
    notifyListeners();

    if (!kIsWeb) {
      // The picker's own native-side access window already closed by
      // the time this Dart code runs (AppDelegate.swift stops it right
      // after creating the bookmark) - must re-open it here for the
      // actual clone, and close it again afterward. Matched 1:1, not
      // left open across the whole app lifecycle.
      final accessPath = await _vaultFolder.startAccessing(bookmark);
      if (accessPath == null) {
        return _fail(const StepFailure(LinkingError.vaultFolderAccessLost));
      }
      try {
        final git = GitServiceImpl(
          bareRepoPath: bareRepoPath,
          localVaultPath: accessPath,
          sshHost: desktopIp,
          sshUser: desktopUser,
          sshPrivateKeyPath: _privateKeyPath!,
          sshPublicKeyPath: _publicKeyPath!,
          sshPort: sshPort,
        );
        final result = await git.pullFromBareRepo();
        if (result case StepFailure()) {
          return _fail(result);
        }
      } finally {
        await _vaultFolder.stopAccessing(bookmark);
      }
    }

    await _verifySync();
  }

  Future<void> _verifySync() async {
    _step = LinkingStep.verifySync;
    notifyListeners();

    // The one thing Synclocal can genuinely check from its own sandbox
    // is whether the download actually produced real files - it cannot
    // see into Obsidian to confirm the folder is displayed as a vault
    // there (no cross-app introspection on iOS).
    if (!kIsWeb && _pickedVaultBookmark != null) {
      final accessPath = await _vaultFolder.startAccessing(_pickedVaultBookmark!);
      if (accessPath == null) {
        return _fail(const StepFailure(LinkingError.vaultFolderAccessLost));
      }
      try {
        final gitDirExists = await Directory('$accessPath/.git').exists();
        final isEmpty = await Directory(accessPath).list().isEmpty;
        if (!gitDirExists || isEmpty) {
          return _fail(const StepFailure(LinkingError.cloneVerificationFailed));
        }
      } finally {
        await _vaultFolder.stopAccessing(_pickedVaultBookmark!);
      }
    }

    _step = LinkingStep.complete;
    _isRunning = false;
    notifyListeners();
  }

  // ── UI strings ─────────────────────────────────────────────────────────────

  String? get currentInstruction => switch (_step) {
    LinkingStep.awaitingVaultCreation =>
      'First, create a new vault in $kNoteAppName:\n\n'
      'Tap OPEN ${kNoteAppName.toUpperCase()}, then in $kNoteAppName:\n'
      'Create a vault → Continue without sync →\n'
      'name it "Synclocal" → Create a vault\n\n'
      'Come back here when you\'re done.',

    LinkingStep.pickingVaultFolder =>
      'Now select the vault you just created:\n\n'
      'Tap SELECT VAULT FOLDER, then browse to\n'
      'On My iPhone → $kNoteAppName → Synclocal',

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
