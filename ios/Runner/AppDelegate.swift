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
  if ProcessInfo.processInfo.environment["SYNCLOCAL_NEVER_SET"] != nil {
    _ = git_libgit2_init_ref()
    _ = git_libgit2_shutdown_ref()
  }
}

// Vault folder picker + security-scoped bookmark bridge (2026-08-09).
//
// Root cause this exists: real user documentation of years of working
// Working Copy + Obsidian usage showed the actual working direction is
// the OPPOSITE of what Synclocal originally assumed. Obsidian creates
// and owns its vault folder itself (on-device, "Continue without
// sync"); a separate sync app can only gain write access to that
// folder afterward, via iOS's real cross-app folder picker - the same
// mechanism Working Copy's "Link Repository to -> Directory" screen
// uses under the hood. Synclocal had it backwards: cloning into its
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

  func register(with messenger: FlutterBinaryMessenger, rootViewController: UIViewController) {
    let channel = FlutterMethodChannel(
      name: "synclocal/vault_folder",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "pickFolder":
        self.pickFolder(from: rootViewController, result: result)
      case "startAccessing":
        self.startAccessing(call: call, result: result)
      case "stopAccessing":
        self.stopAccessing(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func pickFolder(from rootViewController: UIViewController, result: @escaping FlutterResult) {
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
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if let controller = window?.rootViewController as? FlutterViewController {
      vaultFolderChannel.register(with: controller.binaryMessenger, rootViewController: controller)
    }
    return launched
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
