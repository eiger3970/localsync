// features/linking/linking_controller.dart
//
// Drives the vault setup sequence.
//
// Rewritten 2026-08-09 with the flow direction corrected - see
// linking_state.dart's header comment and lib/STRUCTURE.md for the full
// finding. Obsidian creates and owns its vault folder first; Localsync
// requests access to it afterward via iOS's real folder picker
// (VaultFolderService), obtaining a security-scoped bookmark. The
// clone happens into that externally-owned folder, not Localsync's own
// private Documents directory.
//
// Resumes on AppLifecycleState.resumed via lifecycle_observer.dart.

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../services/database_service.dart';
import '../../services/device_name.dart';
import '../../services/git_service.dart';
import '../../services/ios_app_service.dart';
import '../../services/ssh_key_paths.dart';
import '../../services/vault_folder_service.dart';
import '../../constants.dart';
import '../../models/repository.dart';
import 'linking_state.dart';

class LinkingController extends ChangeNotifier {
  final String desktopUser;
  // 2026-08-20: was final - real user feedback, "this is difficult for
  // users, I need to build this in." The desktop's IP is a real-world
  // value that drifts (USB tether vs hotspot vs a DHCP reassignment -
  // all three have actually happened across this project's sessions),
  // and a build-time constant meant every drift needed a code edit and
  // a full rebuild+resideload just to reconnect. Now mutable, with a
  // setter that persists the override (see database_service.dart's
  // getDesktopIp/setDesktopIp) so a user can fix this themselves
  // on-device, no rebuild required.
  String desktopIp;
  // 2026-08-20: was final - real multi-repo gap. Every "Add another
  // vault" attempt pointed at the exact same bare repo regardless of
  // which folder was picked, since this never varied. Now mutable,
  // same override pattern as desktopIp (see database_service.dart's
  // getBareRepoPath/setBareRepoPath) - the Settings screen lets a user
  // set a different target *before* linking a new vault, so a second,
  // genuinely separate vault can sync to its own separate bare repo.
  String bareRepoPath;
  final int sshPort;

  final IosAppService _iosApps;
  final VaultFolderService _vaultFolder;

  LinkingController({
    required this.desktopUser,
    required this.desktopIp,
    required this.bareRepoPath,
    this.sshPort = 22,
    IosAppService? iosApps,
    VaultFolderService? vaultFolder,
  })  : _iosApps = iosApps ?? IosAppServiceImpl(),
        _vaultFolder = vaultFolder ?? VaultFolderService();

  /// Overwrites [desktopIp] and notifies listeners - used by the
  /// settings dialog (home_screen.dart) once the user saves a
  /// corrected value. Persisting the override is the caller's job
  /// (RepositoryProvider.setDesktopIp) - this only updates the live,
  /// already-running instance so the change takes effect immediately,
  /// no app restart needed.
  void updateDesktopIp(String ip) {
    desktopIp = ip;
    notifyListeners();
  }

  /// Overwrites [bareRepoPath] and notifies listeners - same contract
  /// as [updateDesktopIp]. Takes effect on the *next* vault link, not
  /// retroactively on any already-linked Repository (those keep the
  /// remotePath they were saved with).
  void updateBareRepoPath(String path) {
    bareRepoPath = path;
    notifyListeners();
  }

  LinkingStep _step = LinkingStep.idle;
  StepFailure? _lastFailure;
  bool _isRunning = false;

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

  // 2026-08-27: Tier 0 - which entry point started this run, so
  // linking_screen.dart's _saveRepository() can tag the resulting
  // Repository correctly (see repository.dart's SyncMode doc). Defaults
  // to obsidianVault - every existing entry point (startLinking,
  // startLinkingExistingVault) is unchanged and still means that; only
  // the new startLinkingGenericFolder below sets this to genericFolder.
  SyncMode _syncMode = SyncMode.obsidianVault;
  SyncMode get syncMode => _syncMode;

  // 2026-08-14: real device feedback - after tapping Open in the native
  // folder picker (step 2.6), the screen stayed on the static
  // pickingVaultFolder view (fixed 55% progress bar, no spinner) for
  // ~30s while pickFolder() awaited the native side resolving the
  // security-scoped bookmark, reading as frozen. _step doesn't change
  // to cloning until that await returns, so this needs its own busy
  // flag rather than piggybacking on _step.
  bool _pickingFolder = false;

  LinkingStep get step => _step;
  StepFailure? get lastFailure => _lastFailure;
  bool get isRunning => _isRunning;
  bool get pickingFolder => _pickingFolder;
  String? get pickedVaultPath => _pickedVaultPath;
  String? get pickedVaultBookmark => _pickedVaultBookmark;

  double get progress => switch (_step) {
        LinkingStep.idle => 0.0,
        LinkingStep.checkingPairing => 0.10,
        LinkingStep.awaitingVaultCreation => 0.30,
        LinkingStep.pickingVaultFolder => 0.55,
        LinkingStep.cloning => 0.80,
        LinkingStep.verifySync => 0.95,
        LinkingStep.complete => 1.0,
        LinkingStep.failed => 0.0,
      };

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<void> startLinking() async {
    assert(_step == LinkingStep.idle || _step == LinkingStep.failed);
    _reset();
    _isRunning = true;
    notifyListeners();
    await _checkPairing(newVault: true);
  }

  // 2026-08-21: real redesign target flagged by the user (see the
  // "Add another vault" flowchart artifact published this session) -
  // every link attempt used to run the full 11-step "create a vault
  // from nothing" checklist (awaitingVaultCreation), even when the
  // user already has a real, existing Obsidian vault to link - the
  // checklist has nothing to offer in that case, it's pure friction.
  // This is the shortcut: skip straight to pickingVaultFolder, same
  // pairing/Obsidian-installed preconditions still checked first.
  Future<void> startLinkingExistingVault() async {
    assert(_step == LinkingStep.idle || _step == LinkingStep.failed);
    _reset();
    _isRunning = true;
    notifyListeners();
    await _checkPairing(newVault: false);
  }

  // 2026-08-27: Tier 0 entry point (docs/product-tiers.md) - "alpha
  // testers aren't ready for PKM... need the free tier for them." Same
  // pairing precondition as every other entry point (a real SSH keypair
  // still has to exist), but genuinely no Obsidian precondition at all -
  // unlike _skipToPickingFolder below, this never checks
  // isObsidianInstalled(), since a plain-file-sync user may not have
  // Obsidian on their phone at all. Lands on the same pickingVaultFolder
  // step and reuses pickVaultFolder()/_cloneInto() unchanged - the
  // native folder-picker + security-scoped-bookmark mechanism
  // (VaultFolderService) was never actually Obsidian-specific at the
  // platform level, only named for the one thing it was first built for.
  Future<void> startLinkingGenericFolder() async {
    assert(_step == LinkingStep.idle || _step == LinkingStep.failed);
    _reset();
    _syncMode = SyncMode.genericFolder;
    _isRunning = true;
    notifyListeners();
    await _checkPairingGeneric();
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
    // 2026-08-14: real device feedback - tapping OPEN OBSIDIAN from the
    // complete screen opened Obsidian's last-active vault, not the one
    // Localsync just linked, since a bare "obsidian://" open can't
    // target a specific vault. Once a vault folder has actually been
    // picked (_pickedVaultPath set), pass its folder name - which is
    // the vault's display name, since that's exactly the folder the
    // user just selected inside On My iPhone/Obsidian/<vault name> -
    // so Obsidian switches straight to it. Before a vault is picked
    // (the page 3 "OPEN OBSIDIAN" swipe, used to create the vault in
    // the first place) there's nothing to target yet, so this still
    // falls back to a bare open.
    final vaultName = _pickedVaultPath?.split('/').last;
    final result = await _iosApps.openObsidian(vaultName: vaultName);
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

    // Set and notified before the await below, so the UI reacts the
    // instant the button is tapped - not just once _step eventually
    // changes to cloning.
    _pickingFolder = true;
    notifyListeners();

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
    } finally {
      _pickingFolder = false;
    }
    if (result == null) {
      // User cancelled the picker - stay on this step, let them retry.
      notifyListeners();
      return;
    }
    await _cloneInto(result.path, result.bookmark);
  }

  void reset() {
    _reset();
    notifyListeners();
  }

  // ── Steps ──────────────────────────────────────────────────────────────────

  Future<void> _checkPairing({required bool newVault}) async {
    _step = LinkingStep.checkingPairing;
    notifyListeners();

    final privateKeyPath = await SshKeyPaths.privateKeyPath();
    final publicKeyPath = await SshKeyPaths.publicKeyPath();

    if (!kIsWeb) {
      final hasKeypair = await _keypairExists(privateKeyPath, publicKeyPath);
      if (!hasKeypair) {
        return _fail(const StepFailure(LinkingError.pairingNotComplete));
      }
    }

    _privateKeyPath = privateKeyPath;
    _publicKeyPath = publicKeyPath;
    if (newVault) {
      await _awaitVaultCreation();
    } else {
      await _skipToPickingFolder();
    }
  }

  // 2026-08-27: Tier 0's pairing check - same keypair precondition as
  // _checkPairing above, deliberately duplicated rather than adding a
  // third branch to that method's newVault bool, since the two are
  // conceptually different gates (which vault-setup step comes next vs.
  // whether Obsidian needs to be installed at all) and keeping them
  // separate reads clearer than a bool that would otherwise need to
  // become an enum for one call site.
  Future<void> _checkPairingGeneric() async {
    _step = LinkingStep.checkingPairing;
    notifyListeners();

    final privateKeyPath = await SshKeyPaths.privateKeyPath();
    final publicKeyPath = await SshKeyPaths.publicKeyPath();

    if (!kIsWeb) {
      final hasKeypair = await _keypairExists(privateKeyPath, publicKeyPath);
      if (!hasKeypair) {
        return _fail(const StepFailure(LinkingError.pairingNotComplete));
      }
    }

    _privateKeyPath = privateKeyPath;
    _publicKeyPath = publicKeyPath;
    _step = LinkingStep.pickingVaultFolder;
    notifyListeners();
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

  // 2026-08-21: existing-vault shortcut's second half - same Obsidian-
  // installed precondition as _awaitVaultCreation (still genuinely
  // needed either way), but lands straight on pickingVaultFolder
  // instead of showing the from-scratch creation checklist.
  Future<void> _skipToPickingFolder() async {
    if (!kIsWeb) {
      final installed = await _iosApps.isObsidianInstalled();
      if (!installed) {
        return _fail(const StepFailure(LinkingError.obsidianNotInstalled));
      }
    }

    _step = LinkingStep.pickingVaultFolder;
    notifyListeners();
  }

  Future<void> _cloneInto(String path, String bookmark) async {
    _pickedVaultPath = path;
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
        // 2026-08-26: same deviceName resolution as repository_provider
        // .dart's _runLocked/home_screen.dart - needed now that a real
        // merge (not just clone-or-fast-forward) can happen here too,
        // and a merge commit needs a real author.
        final savedName = await DatabaseService().getDeviceName();
        final deviceName = (savedName != null && savedName.trim().isNotEmpty)
            ? savedName
            : await defaultDeviceName();
        final git = GitServiceImpl(
          bareRepoPath: bareRepoPath,
          localVaultPath: accessPath,
          sshHost: desktopIp,
          sshUser: desktopUser,
          sshPrivateKeyPath: _privateKeyPath!,
          sshPublicKeyPath: _publicKeyPath!,
          sshPort: sshPort,
          deviceName: deviceName,
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

    // The one thing Localsync can genuinely check from its own sandbox
    // is whether the download actually produced real files - it cannot
    // see into Obsidian to confirm the folder is displayed as a vault
    // there (no cross-app introspection on iOS).
    if (!kIsWeb && _pickedVaultBookmark != null) {
      final accessPath =
          await _vaultFolder.startAccessing(_pickedVaultBookmark!);
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

  // 2026-08-14: numbered checklist for the vault-creation screen ("1.1",
  // "1.2", ... in the UI) - same steps as the joined string below, kept
  // as a list so the checklist widget and the fallback instruction
  // string can't drift out of sync with each other.
  //
  // Verified against iOS 26.1 / Obsidian 1.12.4 (2026-08-14). This
  // recipe is version-specific - Obsidian's own vault-management UI is
  // what dictates these exact steps, so a future Obsidian update could
  // silently break it. Re-verify against the real device before
  // trusting this list if it's been a while since the versions above.
  //
  // 2026-08-18: the exact recipe, verbatim, per direct correction - not
  // a reconstructed/summarized version. [[project_synclocal_vault_recipe]]'s
  // "11 Create Obsidian Vault on Phone" and "Failed to resolve path"
  // sections were previously treated as two competing candidates for
  // "the trick that creates a new path on the iPhone" and only one was
  // picked (2026-08-12's "Final steps confirmed correct" note). That
  // was wrong - both pieces belong together, in this exact order: New
  // tab (right after the vault opens), THEN the force-close/reopen/
  // force-close cycle. The 2026-08-19 simplification to a single force
  // close, and this file's own earlier partial revert (reopen/close
  // without "New tab"), were both incomplete versions of this recipe -
  // real device testing tonight confirmed the incomplete versions don't
  // work (fresh vault ended up completely empty on disk).
  // 2026-08-20: "1.12 reopen Obsidian / 1.13 force close Obsidian
  // again" removed, per direct repeated instruction ("redundant as
  // discussed at much length previously... remove them") - confirmed
  // safe by the user's own real relink today, ticked as formality
  // without literally performing them, real vault linked successfully.
  // Caveat worth knowing if fresh *empty* vault creation ever breaks
  // again: the 2026-08-19 comment above this list found the reopen/
  // force-close-again cycle necessary specifically for that case
  // ("fresh vault ended up completely empty on disk" without it) - this
  // removal is a conscious tradeoff for the "add another" case, not a
  // re-verification that fresh creation still works without it.
  List<String> get vaultCreationSteps => [
        'swipe up to open $kNoteAppName',
        'swipe from left to right',
        'tap vault (bottom left)',
        'tap Manage vaults...',
        'tap Create new vault',
        'Vault name: <Enter name...>',
        'Store in iCloud: off by default',
        'tap Create',
        'new vault opens',
        'New tab',
        'force close $kNoteAppName',
      ];

  // 2026-08-14: same idea as vaultCreationSteps, for the folder-picker
  // screen (2.1-2.6) - what the user does inside iOS's native document
  // picker after tapping VAULT FOLDER, which Localsync has no
  // visibility into once it's open.
  List<String> get vaultFolderSteps => [
        'swipe up to open VAULT FOLDER',
        'tap Browse',
        'tap On My iPhone (Browse/Locations/On My iPhone)',
        'tap $kNoteAppName folder',
        'tap the vault',
        'tap Open',
        // 2026-08-15: was a separate warning Text below the checklist -
        // folded into the checklist itself per explicit direction, even
        // though it's not an action to perform (it's a heads-up), so
        // the whole sequence lives in one tickable list rather than
        // being split across two different UI elements.
        'phone will pause up to a minute, downloading your notes',
      ];

  // 2026-08-11: "First," -> a step counter ("1 of 2") per explicit
  // direction - there are exactly two real user actions in this whole
  // flow (create the vault, then pick its folder); the other steps
  // (pairing check, clone, verify) run autonomously with a spinner, not
  // something the user does, so they're not counted here.
  // 2026-08-11: steps below are the user's own dictated sequence,
  // transcribed exactly, not localsync's previous guess - "do not
  // change my steps, exactly what I have is the secret recipe" (real
  // Obsidian iOS + Working Copy research, hard-won over real trial and
  // error - see [[project_localsync_vault_recipe]] memory /
  // STRUCTURE.md's "Protected IP" section). Final steps corrected
  // 2026-08-12: the user's own document has two different candidates
  // for "the trick that creates a new path on the iPhone" - a single
  // "New tab -> force close" (section 11) vs. a real close/reopen/
  // close cycle from the "Failed to resolve path" section. User
  // confirmed the latter is correct when shown both side by side.
  String? get currentInstruction => switch (_step) {
        LinkingStep.awaitingVaultCreation =>
          '1 of 2: create a new vault in $kNoteAppName:\n\n'
              '${vaultCreationSteps.join(' → ')}\n\n'
              'Come back here when you\'re done.',

        LinkingStep.pickingVaultFolder =>
          '2 of 2: tap the vault you just created:\n\n'
              '${vaultFolderSteps.join(' → ')}',
        _ => null,
      };

  String get stepLabel => switch (_step) {
        LinkingStep.checkingPairing => 'Checking setup…',
        LinkingStep.cloning => 'Downloading your notes…',
        LinkingStep.verifySync => 'Verifying…',
        _ => 'Working…',
      };

  String get stepSubtitle => switch (_step) {
        LinkingStep.cloning => 'Connecting via SSH and copying your vault',
        _ => 'iOS is processing - this is not frozen',
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
    _step = LinkingStep.failed;
    _isRunning = false;
    notifyListeners();
  }

  // 2026-08-18: real device bug - "Add another vault" landed straight
  // on a stale "Something stopped" failure screen from a PREVIOUS
  // linking attempt, retrying the SAME old bookmark/path (still
  // showing the earlier PathAccessException) instead of starting a
  // genuinely new attempt. This only ever cleared _step/_lastFailure/
  // _isRunning - the picked vault path/bookmark from the prior attempt
  // survived untouched, so even callers that do reset the flow state
  // were still handing the next clone the old, bad bookmark.
  void _reset() {
    _step = LinkingStep.idle;
    _lastFailure = null;
    _isRunning = false;
    _pickedVaultPath = null;
    _pickedVaultBookmark = null;
    _pickingFolder = false;
    _syncMode = SyncMode.obsidianVault;
  }
}
