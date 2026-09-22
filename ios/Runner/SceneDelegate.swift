import Flutter
import UIKit

// 2026-09-18: real bug, found after 6 rounds of chasing "Widget gif no
// message seen" through Dart-side code that all traced back correctly
// to AppDelegate.swift's application(_:didFinishLaunchingWithOptions:)/
// application(_:open:options:) - which turned out to be dead code for
// this exact purpose. This app declares UIApplicationSceneManifest in
// Info.plist (real UIScene support), and under that architecture iOS
// routes URL-open events (cold launch via connectionOptions, warm via
// openURLContexts) through THIS delegate instead - the AppDelegate
// overrides never fire at all for a localsync:// tap, which is why
// PendingWidgetAction.value was never actually being set and every
// debug SnackBar downstream in Dart correctly reported "null."
class SceneDelegate: FlutterSceneDelegate {

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    // Cold launch via widget tap - the real equivalent of AppDelegate's
    // own application(_:didFinishLaunchingWithOptions:) override, which
    // never fires under this app's real UIScene architecture.
    //
    // 2026-09-22: real crash, live, single tap - iOS can ALSO fire
    // scene(_:openURLContexts:) below with this exact same URL moments
    // after this cold-launch delivery - a real, documented double
    // delivery for one tap, not a guess. PendingWidgetAction.accept()
    // (see its own comment in AppDelegate.swift) drops the repeat
    // instead of both callbacks each independently believing they saw a
    // fresh tap.
    if let url = connectionOptions.urlContexts.first?.url, url.scheme == "localsync" {
      PendingWidgetAction.accept(url)
    }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    // Warm launch (scene already connected/running) - the real
    // equivalent of AppDelegate's own application(_:open:options:)
    // override, which never fires under this app's real UIScene
    // architecture. See willConnectTo above for why this goes through
    // accept() now instead of a direct assignment - this callback can
    // fire a second time for the SAME cold-launch tap willConnectTo
    // already handled, not just for genuine later warm-launch taps.
    if let url = URLContexts.first?.url, url.scheme == "localsync" {
      PendingWidgetAction.accept(url)
    }
  }
}
