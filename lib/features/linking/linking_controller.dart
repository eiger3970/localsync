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
import '../../services/localsync_folder.dart';
import '../../services/files_app_path.dart';

class LinkingController extends ChangeNotifier {
  // 2026-08-28: was final, hardcoded to this developer's own desktop
  // login ('rapi5') at every real call site - found while checking an
  // unrelated question. Any real customer, whose desktop username isn't
  // 'rapi5', would have every SSH connection fail immediately - this
  // only ever worked because every device test so far ran against this
  // exact machine. Same override pattern as desktopIp/bareRepoPath now.
  String desktopUser;
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
  // 2026-09-02: real gap found, live - "this all needs to be available
  // to a user installing the app, so I can do it without you." Same
  // override pattern as bareRepoPath above (see database_service.dart's
  // getDesktopVaultPath/setDesktopVaultPath) - lets a user reconnecting
  // to an EXISTING desktop vault point the auto-installed desktop sync
  // cron job (git_service.dart's _ensureDesktopSyncInstalled) at it,
  // without a manual crontab edit. Null/empty means "no override, the
  // cron job's own safe default is used" - same as a fresh setup today.
  String? desktopVaultPath;
  final int sshPort;

  final IosAppService _iosApps;
  final VaultFolderService _vaultFolder;

  LinkingController({
    required this.desktopUser,
    required this.desktopIp,
    required this.bareRepoPath,
    this.desktopVaultPath,
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

  /// Overwrites [desktopUser] and notifies listeners - same contract as
  /// [updateDesktopIp].
  void updateDesktopUser(String user) {
    desktopUser = user;
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

  /// Overwrites [desktopVaultPath] and notifies listeners - same
  /// contract as [updateDesktopIp].
  void updateDesktopVaultPath(String path) {
    desktopVaultPath = path;
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

  // 2026-08-27: set by the new "what do you want to sync?" chooser
  // (sync_choice_screen.dart) before it navigates into this screen, so
  // the drag-to-pair gesture in _IdleView - the main, most obvious way
  // to start, not just the small text links - lands on the right flow
  // after pairing succeeds (see _pairThenLink's own use of this). Null
  // means "no choice made yet" (existing entry points - "Vault - add
  // another" from the kebab menu, say - skip the chooser and keep their
  // prior direct behavior unchanged).
  SyncMode? preferredMode;

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
    _clearCachedRepoLocationForNewVault();
    _isRunning = true;
    notifyListeners();
    await _checkPairing(newVault: true);
  }

  // 2026-09-22: real near-miss, live - a "fresh install" test ended up
  // silently reusing the REAL production bareRepoPath/desktopVaultPath
  // from main.dart's own DatabaseService().getBareRepoPath()/
  // getDesktopVaultPath() restore-on-launch (see that file's own
  // comments) - iOS commonly restores an app's shared_preferences
  // (NSUserDefaults) from an iCloud backup on reinstall, so a "fresh
  // install" doesn't actually guarantee a clean slate the way it does
  // on, say, a fresh Android install. Those two fields are genuinely
  // useful to keep cached for startLinkingExistingVault() ("I already
  // have a vault, reconnect it" - deliberately wants the SAME desktop
  // bare repo) - but for a genuinely NEW vault/folder (this method and
  // startLinkingGenericFolder below), silently reusing a real file-path
  // value the user never saw or confirmed is exactly what almost
  // caused a real production vault to get corrupted today. Both
  // "brand new" entry points now force these back to empty first, so a
  // fresh bare repo genuinely gets created fresh - same "leave blank
  // for a fresh one" behavior docs/desktop-setup.md already documents,
  // now actually guaranteed rather than accidental.
  void _clearCachedRepoLocationForNewVault() {
    bareRepoPath = '';
    desktopVaultPath = '';
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
    _clearCachedRepoLocationForNewVault();
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
  // 2026-09-24: real ask, live - "users will pick wrong paths and sync
  // might wipe their data... customers need a prompt informing them
  // their data is backed up before, then a reminder after where." The
  // backup itself already existed (vault_backup.dart, run by
  // pullFromBareRepo before the first clone touches a non-empty
  // folder); nothing TOLD anyone. [confirm] is the screen's dialog: it
  // gets what's in the picked folder and returns whether to go ahead.
  // Without it (tests, web stub) behaviour is unchanged.
  String? _lastVaultBackupRelPath;
  /// Where the first clone backed up the folder's earlier content
  /// (vault-relative), or null if it was empty - for the success screen.
  String? get lastVaultBackupRelPath => _lastVaultBackupRelPath;

  Future<void> pickVaultFolder(
      {Future<bool> Function(VaultFolderCheck check)? confirm}) async {
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
    if (confirm != null) {
      final check = await _checkPickedFolder(result.bookmark);
      if (check != null && check.needsPrompt && !await confirm(check)) {
        notifyListeners();
        return; // stays on "pick your vault folder" - pick again
      }
    }
    await _cloneInto(result.path, result.bookmark);
  }

  /// The desktop repo path [bookmark]'s folder is already linked to
  /// (its .git/config origin), or null - see _cloneInto.
  Future<String?> _existingRepoPathFor(String bookmark) async {
    final path = await _vaultFolder.startAccessing(bookmark);
    if (path == null) return null;
    try {
      final config = File('$path/.git/config');
      if (!await config.exists()) return null;
      return existingOriginRepoPath(await config.readAsString());
    } catch (_) {
      return null;
    } finally {
      await _vaultFolder.stopAccessing(bookmark);
    }
  }

  /// Looks inside the picked folder (read-only) - null if it can't be
  /// opened, in which case the clone step's own access check reports it.
  Future<VaultFolderCheck?> _checkPickedFolder(String bookmark) async {
    final path = await _vaultFolder.startAccessing(bookmark);
    if (path == null) return null;
    String name(FileSystemEntity e) =>
        e.uri.pathSegments.lastWhere((x) => x.isNotEmpty);
    try {
      final dir = Directory(path);
      final entries = await dir
          .list(followLinks: false)
          .where((e) => name(e) != '.DS_Store')
          .toList();
      final childVaults = <String>[];
      for (final e in entries) {
        if (e is Directory && await Directory('${e.path}/.obsidian').exists()) {
          childVaults.add(name(e));
        }
      }
      return VaultFolderCheck(
        absolutePath: path,
        folderName: name(dir),
        isEmpty: entries.isEmpty,
        isVault: await Directory('$path/.obsidian').exists(),
        childVaults: childVaults..sort(),
        backupFolder: localSyncFolder(path),
      );
    } catch (_) {
      return null;
    } finally {
      await _vaultFolder.stopAccessing(bookmark);
    }
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

  // 2026-08-28: real feedback, live - "tier0 or obsidian have both
  // paired with key and desktop password right? that step... isn't
  // needed" for a returning user. LinkingScreen's own Stage 1 (drag key
  // into lock + retype desktop password) always started from scratch
  // on every entry, with nothing checking whether this phone already
  // has a working keypair from an earlier pairing - true for the IAP
  // unlock path specifically, but really for any return visit
  // (kebab menu's "add another", too). Same file-existence check
  // _checkPairing/_checkPairingGeneric above already use, exposed
  // publicly so LinkingScreen's initState can skip Stage 1 entirely
  // when it would just be repeating a completed step.
  Future<bool> hasExistingKeypair() async {
    final privateKeyPath = await SshKeyPaths.privateKeyPath();
    final publicKeyPath = await SshKeyPaths.publicKeyPath();
    return _keypairExists(privateKeyPath, publicKeyPath);
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
    // 2026-09-22: real bug, live, found immediately after today's own
    // safety fix (_clearCachedRepoLocationForNewVault) shipped - "Git
    // bare repo not found at the configured path on your desktop." That
    // fix correctly stops a new vault from silently reusing a cached
    // real-vault path, but left bareRepoPath as a literal empty string
    // rather than turning "blank" into an actual fresh path - confirmed
    // directly by reproducing the exact shell command
    // _ensureBareRepoExists() runs with an empty path: `git init --bare
    // ''` genuinely fails ("fatal: cannot mkdir : No such file or
    // directory"), which git_service.dart's own _diagnose() then
    // classifies as exactly this error (its 'no such file' branch).
    // "Leave blank for a fresh one" (docs/desktop-setup.md) was never
    // actually implemented as generating a fresh path - it only worked
    // before by accident, via whatever stale cached value happened to
    // already be sitting in bareRepoPath. Generates a real one now,
    // named after the vault folder just picked (sanitized to safe git-
    // path characters) plus a timestamp, so it's both meaningful and
    // guaranteed not to collide with anything else on the desktop.
    // 2026-09-24: real error, live, first install on a phone whose vault
    // was already synced - "This vault folder is already linked to a
    // different bare repo than the one in Settings. ... This folder's
    // repo: .../Md_files_bare.git  Settings' repo: Documents/Git/
    // LocalSync/Obsidian_phone_vault_1790254923967.git". Obsidian setup
    // always runs startLinking (new vault), which clears the cached repo
    // path (the 2026-09-22 safety fix) and generated a brand-new desktop
    // repo name here - for a vault that already HAS one. The identity
    // check caught it (nothing was damaged), but setup could never
    // finish. A folder already linked to a desktop repo now keeps that
    // link: the folder's own git config is the truth about which repo
    // its notes belong to, not a freshly invented name.
    if (bareRepoPath.trim().isEmpty && !kIsWeb) {
      final existing = await _existingRepoPathFor(bookmark);
      if (existing != null) bareRepoPath = existing;
    }
    if (bareRepoPath.trim().isEmpty) {
      final segments = path.split('/').where((s) => s.isNotEmpty).toList();
      final folderName = segments.isNotEmpty ? segments.last : 'vault';
      final safeName = folderName.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
      final ts = DateTime.now().millisecondsSinceEpoch;
      bareRepoPath = 'Documents/Git/LocalSync/${safeName}_$ts.git';
    }
    _step = LinkingStep.cloning;
    notifyListeners();

    if (!kIsWeb) {
      // The picker's own native-side access window already closed by
      // the time this Dart code runs (AppDelegate.swift stops it right
      // after creating the bookmark) - must re-open it here for the
      // actual clone, and close it again afterward. Matched 1:1, not
      // left open across the whole app lifecycle.
      //
      // 2026-09-24: real error, live, first setup - "GIT_ERROR_NET:
      // Invalid url: malformed hostname." PairingController already
      // refuses an empty desktop address, but this clone step never
      // checked, so an address lost after pairing (Settings filled by a
      // QR scan and left without saving) reached libgit2 as
      // "ssh://user@:22/..." - a raw git error instead of the plain fix.
      // Same error and wording as the pairing check.
      final missing = [
        if (desktopUser.trim().isEmpty) 'Desktop username',
        if (desktopIp.trim().isEmpty || desktopIp.trim().contains(' '))
          'Desktop IP address',
      ];
      if (missing.isNotEmpty) {
        return _fail(StepFailure(LinkingError.desktopNotConfigured,
            debugDetail: 'Empty in Settings: ${missing.join(', ')}'));
      }
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
          // 2026-09-25: this folder's own desktop path, never another
          // synced folder's (see DatabaseService.getDesktopVaultPathFor).
          desktopVaultPath:
              await DatabaseService().getDesktopVaultPathFor(bareRepoPath),
        );
        final result = await git.pullFromBareRepo();
        if (result case StepFailure()) {
          return _fail(result);
        }
        _lastVaultBackupRelPath = git.lastBackupRelPath;
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
  // 2026-09-24: "@app " tags - each step's app shown as a badge, see
  // widgets/app_badge.dart ("needs context for humans").
  List<String> get vaultCreationSteps => [
        '@localsync swipe up to open $kNoteAppName',
        '@obsidian swipe from left to right',
        '@obsidian tap vault (bottom left)',
        '@obsidian tap Manage vaults...',
        '@obsidian tap Create new vault',
        '@obsidian Vault name: <Enter name...>',
        '@obsidian Store in iCloud: off by default',
        '@obsidian tap Create',
        '@obsidian new vault opens',
        '@obsidian New tab',
        '@phone force close $kNoteAppName (swipe up from the bottom, flick it away)',
      ];

  // 2026-08-14: same idea as vaultCreationSteps, for the folder-picker
  // screen (2.1-2.6) - what the user does inside iOS's native document
  // picker after tapping VAULT FOLDER, which Localsync has no
  // visibility into once it's open.
  // 2026-08-28: found still hardcoded to the Obsidian vault flow even
  // after Tier 0 (startLinkingGenericFolder) was added 2026-08-27 to
  // reuse this same step - a generic-folder user has no vault/On My
  // iPhone/$kNoteAppName folder to navigate to, so the old text was
  // just wrong for that flow, not merely unpolished. Now mode-aware;
  // the underlying native picker (_vaultFolder.pickFolder()) was
  // always folder-agnostic, only this copy wasn't.
  List<String> get vaultFolderSteps => _syncMode == SyncMode.genericFolder
      ? [
          '@localsync swipe up to open the folder picker',
          '@files tap Browse',
          '@files navigate to the folder you want to sync',
          '@files tap the folder to select it',
          '@files tap Open',
          '@localsync phone will pause up to a minute, checking the folder',
        ]
      : [
          '@localsync swipe up to open VAULT FOLDER',
          '@files tap Browse',
          '@files tap On My iPhone (Browse/Locations/On My iPhone)',
          '@files tap $kNoteAppName folder',
          // 2026-09-24: "new users won't be 100% sure what to pick with
          // no vaults or multiple vaults" - name it by what they did in
          // step 1, not "the vault".
          '@files tap your vault - the name you typed in step 1',
          '@files tap Open',
          // 2026-08-15: was a separate warning Text below the checklist -
          // folded into the checklist itself per explicit direction, even
          // though it's not an action to perform (it's a heads-up), so
          // the whole sequence lives in one tickable list rather than
          // being split across two different UI elements.
          '@localsync phone will pause up to a minute, downloading your notes',
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

        LinkingStep.pickingVaultFolder => _syncMode == SyncMode.genericFolder
            // 2026-08-28: real feedback, live - "it pulled files
            // automatically from somewhere from the desktop... this is
            // just a surprise. I need informed users." Same "must be
            // 100% informed" principle already applied to the git-install
            // consent screen, here for the actual file copy itself -
            // nothing previously told the user that picking a folder
            // triggers an automatic pull from the desktop's configured
            // path, with whatever's already stored there landing in the
            // folder they pick. Explicit disclosure now comes first,
            // before the "pick empty" tip that already existed - that
            // tip explained what to avoid, never what was actually about
            // to happen.
            ? 'pick the folder to sync:\n\n'
                '${vaultFolderSteps.join(' → ')}\n\n'
                // 2026-08-28, follow-up: "I need the desktop to inform
                // the user what the path is" - real, buildable ask.
                // bareRepoPath/desktopUser/desktopIp are already known
                // here (typed into Settings before this screen was ever
                // reached), so the disclosure can name the exact source
                // instead of pointing back at "Settings" as if it were
                // somewhere else to go check.
                'What happens next: whatever is already stored on your '
                'desktop at $desktopUser@$desktopIp:$bareRepoPath gets '
                'copied into the folder you pick - automatically, as '
                'soon as you tap Open.\n\n'
                'Tip: pick or create an empty folder just for this '
                '(e.g. a new "Sync" folder), rather than an existing '
                'folder full of other files - keeps things tidy as it '
                'grows.'
            : '2 of 2: tap the vault you just created:\n\n'
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
    _lastVaultBackupRelPath = null;
    _lastFailure = null;
    _isRunning = false;
    _pickedVaultPath = null;
    _pickedVaultBookmark = null;
    _pickingFolder = false;
    _syncMode = SyncMode.obsidianVault;
  }
}

/// What pickVaultFolder found in the folder the user just picked.
class VaultFolderCheck {
  /// Live path from the picker - for the Files app route shown to the
  /// user (files_app_path.dart), never shown raw.
  final String absolutePath;
  final String folderName;
  final bool isEmpty;
  /// Has its own .obsidian - it's a vault.
  final bool isVault;
  /// Sub-folders that are vaults - picking their parent (e.g. "Obsidian"
  /// instead of "Obsidian_phone_vault") is the likely wrong-folder case.
  final List<String> childVaults;
  /// Where the backup will go inside it, e.g. "LocalSync".
  final String backupFolder;
  const VaultFolderCheck({
    required this.absolutePath,
    required this.folderName,
    required this.isEmpty,
    required this.isVault,
    required this.childVaults,
    required this.backupFolder,
  });

  bool get looksLikeParentOfVaults => !isVault && childVaults.isNotEmpty;

  /// 2026-09-24: real ask, live - "there may be no vault for new installs
  /// also." Obsidian's own top folder (Files: On My iPhone > Obsidian, or
  /// iCloud Drive > Obsidian) with no vault in it yet - linking it would
  /// make Obsidian's whole folder the vault.
  bool get isObsidianTopFolderWithNoVault {
    if (isVault || childVaults.isNotEmpty) return false;
    final route = filesAppRoute(absolutePath);
    return route.length == 2 && route.last == 'Obsidian';
  }

  /// Anything worth stopping to tell the user before linking.
  bool get needsPrompt =>
      !isEmpty || looksLikeParentOfVaults || isObsidianTopFolderWithNoVault;
}
