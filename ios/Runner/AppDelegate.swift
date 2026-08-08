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
  }
}
