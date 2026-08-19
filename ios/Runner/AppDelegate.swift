import Flutter
import UIKit

// Forces the linker to retain these C symbols instead of dead-stripping
// them (2026-08-08: real device hit "Failed to lookup symbol
// 'git_libgit2_init'" - Dart FFI's DynamicLibrary.process()/dlsym() at
// runtime is invisible to the linker at compile time, since nothing in
// Swift/ObjC ever calls these directly - only Dart does, later, via FFI.
// Podfile-level fixes (-all_load, disabled strip, static framework
// linkage) didn't resolve it on their own across three attempts -
// explicitly referencing the symbols here is the more surgical,
// documented fix for this exact Dart-FFI-on-iOS-Release problem.
// See lib/STRUCTURE.md for the full debugging trail.
@_silgen_name("git_libgit2_init")
func git_libgit2_init_ref() -> Int32

@_silgen_name("git_libgit2_shutdown")
func git_libgit2_shutdown_ref() -> Int32

private func retainLibgit2Symbols() {
  // Never actually called in a way that matters - just needs to exist
  // as a real reference so the linker can't prove it's unused.
  if ProcessInfo.processInfo.environment["LOCALSYNC_NEVER_SET"] != nil {
    _ = git_libgit2_init_ref()
    _ = git_libgit2_shutdown_ref()
  }
}

// Vault folder picker + security-scoped bookmark bridge (2026-08-09).
//
// Root cause this exists: real user documentation of years of working
// Working Copy + Obsidian usage showed the actual working direction is
// the OPPOSITE of what Localsync originally assumed. Obsidian creates
// and owns its vault folder itself (on-device, "Continue without
// sync"); a separate sync app can only gain write access to that
// folder afterward, via iOS's real cross-app folder picker - the same
// mechanism Working Copy's "Link Repository to -> Directory" screen
// uses under the hood. Localsync had it backwards: cloning into its
// own private folder and hoping Obsidian could later "open" it - no
// such import path exists in Obsidian's iOS UI.
//
// iOS requires a *security-scoped bookmark* to retain access to a
// folder picked from another app's sandbox across app launches - a
// plain path string is not enough and will fail (this is exactly the
// same class of "path looks valid but access is denied" problem
// STRUCTURE.md already documents for this app's OWN container path
// going stale across reinstalls, just for a different underlying
// reason here). Every access must be bracketed with
// startAccessingSecurityScopedResource()/stopAccessingSecurityScopedResource()
// - Apple's documented pattern - matched 1:1 in the Dart caller.
//
// Uses the string-UTI form of UIDocumentPickerViewController
// ("public.folder", stable since iOS 8) rather than the newer
// UTType-based API, specifically to avoid needing to raise this
// project's iOS 13.0 deployment target or add availability checks -
// deprecated but fully supported, and simplicity won given how many
// build-pipeline days this session has already cost.
class VaultFolderChannel: NSObject, UIDocumentPickerDelegate {
  private var pendingResult: FlutterResult?

  // Fixed 2026-08-09: real device confirmed "tapping SELECT VAULT
  // FOLDER does nothing" - exactly the risk flagged in STRUCTURE.md
  // before this was ever tested. Root cause: register(with:
  // rootViewController:) was called from application(_:
  // didFinishLaunchingWithOptions:) right after super's call, assuming
  // window?.rootViewController already resolved to a live
  // FlutterViewController at that exact point. This app uses the
  // implicit-engine pattern (FlutterImplicitEngineDelegate) - the
  // engine/root view controller isn't guaranteed to exist yet that
  // early; GeneratedPluginRegistrant.register() is deliberately called
  // later, from didInitializeImplicitFlutterEngine, for the same
  // reason. Registration no longer requires a root view controller up
  // front - it's looked up fresh at the moment the picker is actually
  // presented instead, by which point the user has already navigated
  // through several screens and the view controller is definitely live.
  func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "localsync/vault_folder",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "pickFolder":
        self.pickFolder(result: result)
      case "startAccessing":
        self.startAccessing(call: call, result: result)
      case "stopAccessing":
        self.stopAccessing(call: call, result: result)
      case "coordinatedWrite":
        self.coordinatedWrite(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // 2026-08-19: real device finding - a picker resolution the user
  // confirmed working (device name/timestamp all correct at the time)
  // was later found reverted back to its pre-resolution content, byte
  // for byte, with no error surfaced anywhere. Most likely explanation:
  // conflict_scanner.dart's resolveConflict() wrote the file via plain
  // dart:io File.writeAsString(), which is a raw POSIX write - it does
  // not go through NSFileCoordinator, so if Obsidian holds an
  // NSFilePresenter on this vault folder (the normal iOS pattern for a
  // document-based app watching a folder it doesn't exclusively own),
  // Obsidian's own presenter is never told "this file changed
  // externally, reload it" - its in-memory buffer stays stale, and its
  // own next autosave (a timer, or losing focus) blindly overwrites
  // Localsync's write right back to the unresolved version.
  //
  // NSFileCoordinator.coordinate(writingItemAt:) is the OS-level
  // mechanism that exists specifically for this - it notifies every
  // registered NSFilePresenter for the URL before/around the write, so
  // if Obsidian is in fact a presenter here, this gives it the chance
  // to invalidate its cache instead of clobbering it later. NOT yet
  // confirmed on a real device that this actually stops the revert -
  // the presenter-registration theory is the best available
  // explanation given what was observed, not something inspectable
  // from outside Obsidian's own code. dart:io's plain write remains the
  // fallback (vault_folder_service.dart's coordinatedWrite) if this
  // channel call fails for any reason, so behavior never regresses
  // below what it was.
  private func coordinatedWrite(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let path = args["path"] as? String,
          let content = args["content"] as? String
    else {
      result(FlutterError(code: "BAD_ARGS", message: "path and content are required", details: nil))
      return
    }
    let url = URL(fileURLWithPath: path)
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinationError: NSError?
    var writeError: Error?
    coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
      do {
        try content.write(to: coordinatedURL, atomically: true, encoding: .utf8)
      } catch {
        writeError = error
      }
    }
    if let coordinationError = coordinationError {
      result(FlutterError(code: "COORDINATION_FAILED", message: coordinationError.localizedDescription, details: nil))
      return
    }
    if let writeError = writeError {
      result(FlutterError(code: "WRITE_FAILED", message: writeError.localizedDescription, details: nil))
      return
    }
    result(true)
  }

  // Fixed 2026-08-11: real device hit "NO_ROOT_VC" - this app's
  // Info.plist declares UIApplicationSceneManifest, so on iOS 13+ the
  // real window is owned by a UIWindowScene, not
  // UIApplicationDelegate.window (that property is only reliably
  // populated for pre-Scene apps). Looks up the key window via
  // connectedScenes first - the correct modern path - falling back to
  // the old .delegate?.window lookup for safety, then walks any
  // already-presented view controller chain so this doesn't try to
  // double-present on top of something else already on screen.
  private func topViewController() -> UIViewController? {
    let sceneWindow: UIWindow? = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
    let fallbackWindow: UIWindow? = UIApplication.shared.delegate?.window ?? nil
    let keyWindow: UIWindow? = sceneWindow ?? fallbackWindow

    guard var top = keyWindow?.rootViewController else { return nil }
    while let presented = top.presentedViewController {
      top = presented
    }
    return top
  }

  private func pickFolder(result: @escaping FlutterResult) {
    guard let rootViewController = topViewController() else {
      result(FlutterError(code: "NO_ROOT_VC", message: "No root view controller available to present the picker", details: nil))
      return
    }
    pendingResult = result
    let picker = UIDocumentPickerViewController(documentTypes: ["public.folder"], in: .open)
    picker.delegate = self
    picker.allowsMultipleSelection = false
    rootViewController.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first else {
      pendingResult?(nil)
      pendingResult = nil
      return
    }

    guard url.startAccessingSecurityScopedResource() else {
      pendingResult?(FlutterError(code: "ACCESS_DENIED", message: "Could not access the selected folder", details: nil))
      pendingResult = nil
      return
    }
    defer { url.stopAccessingSecurityScopedResource() }

    do {
      // iOS has no .withSecurityScope bookmark option (that's macOS-
      // only) - a plain bookmark created from a URL obtained via the
      // document picker is inherently resolvable with continued
      // security-scoped access later. This is the correct iOS pattern,
      // not a shortcut.
      let bookmark = try url.bookmarkData()
      pendingResult?([
        "path": url.path,
        "bookmark": bookmark.base64EncodedString(),
      ])
    } catch {
      pendingResult?(FlutterError(code: "BOOKMARK_FAILED", message: error.localizedDescription, details: nil))
    }
    pendingResult = nil
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pendingResult?(nil)
    pendingResult = nil
  }

  private func startAccessing(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let bookmarkBase64 = args["bookmark"] as? String,
          let data = Data(base64Encoded: bookmarkBase64) else {
      result(FlutterError(code: "BAD_ARGS", message: "Missing or invalid bookmark", details: nil))
      return
    }

    do {
      var isStale = false
      let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
      guard url.startAccessingSecurityScopedResource() else {
        result(FlutterError(code: "ACCESS_DENIED", message: "Could not resume access to the vault folder", details: nil))
        return
      }
      result(["path": url.path, "stale": isStale])
    } catch {
      result(FlutterError(code: "RESOLVE_FAILED", message: error.localizedDescription, details: nil))
    }
  }

  private func stopAccessing(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let bookmarkBase64 = args["bookmark"] as? String,
          let data = Data(base64Encoded: bookmarkBase64) else {
      result(nil)
      return
    }
    var isStale = false
    if let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) {
      url.stopAccessingSecurityScopedResource()
    }
    result(nil)
  }
}

private let vaultFolderChannel = VaultFolderChannel()

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    retainLibgit2Symbols()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Registered here, not in application(_:didFinishLaunchingWithOptions:)
    // - see VaultFolderChannel.register()'s comment for why.
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "VaultFolderChannel") else {
      return
    }
    vaultFolderChannel.register(with: registrar.messenger())
  }
}
