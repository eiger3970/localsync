# synclocal — lib/ structure

Feature-first layout. Each feature owns its state, controller, and screen.
Services are shared infrastructure injected via Provider.

```
lib/
├── main.dart                        # Provider setup, lifecycle observer registration
├── lifecycle_observer.dart          # AppLifecycleState → LinkingController bridge
│
├── features/
│   ├── linking/                     # THE CORE FEATURE — 8-step automation
│   │   ├── linking_state.dart       # LinkingStep enum, StepResult sealed class, LinkingError
│   │   ├── linking_controller.dart  # State machine driver (ChangeNotifier)
│   │   └── linking_screen.dart      # TODO: step progress UI
│   │
│   ├── sync/                        # Ongoing sync (auto/manual/scheduled)
│   │   ├── sync_controller.dart     # TODO
│   │   └── sync_screen.dart         # TODO: home screen
│   │
│   ├── pairing/                     # WiFi hotspot + QR code SSH key exchange
│   │   ├── pairing_controller.dart  # TODO
│   │   └── pairing_screen.dart      # TODO
│   │
│   └── settings/
│       ├── settings_controller.dart # TODO
│       └── settings_screen.dart     # TODO
│
└── services/                        # Shared, injected infrastructure
    ├── git_service.dart             # Git ops (MVP: delegates to Working Copy)
    ├── ios_app_service.dart         # URL scheme launcher for WC + Obsidian
    ├── vault_service.dart           # Vault path + creation logic
    ├── ssh_service.dart             # TODO: SSH key gen + exchange for pairing
    └── storage_service.dart         # TODO: sqflite + shared_preferences wrapper
```

## Key design decisions

### State machine (not async chain)
The linking sequence parks at steps 4 and 6 waiting for user actions in
external apps. A linear async chain would need artificial delays or polling.
A state machine parks explicitly and resumes on AppLifecycleState.resumed.

### Git library: git2dart (decided 2026-08-08, supersedes Working Copy plan)
- dart-git: push/pull unimplemented, abandoned 2022 - ruled out
- Working Copy URL-scheme delegation: this was the original MVP plan, but
  it means Synclocal doesn't actually sync anything itself - it's fully
  dependent on a separate paid third-party iOS app doing the real work.
  Rejected 2026-08-08: the whole point of the product is to do this
  natively, not depend on Working Copy.
- Earlier note here said "libgit2 FFI: App Store entitlements for .dylib
  are complex" - that concern is about *dynamic* .dylib loading at
  runtime. It doesn't apply to *static* linking via CocoaPods, which is
  how most native-code Flutter plugins ship on iOS (same mechanism any
  other native SDK dependency uses).
- Decision: use `git2dart` (pub.dev, publisher dartgit.dev, FFI bindings
  to libgit2, iOS support via CocoaPods/static linking). Confirmed it
  exposes both `fetch()` and `push()` on its Remote class, plus a
  dedicated iOS setup guide. Verified via live web search 2026-08-08,
  not from training-data memory, because the package landscape here
  changes fast and being wrong wastes real build time.
- Risk to track: git2dart is pre-1.0 (was 0.5.4 as of 2026-08-08),
  young (171 commits, 12 stars) - real maturity risk for something this
  business-critical, even though zero open issues and recent activity
  (published 17 days before that date) are decent signs. Re-check its
  state before leaning on it further if this session's work is resumed
  much later.
- This does NOT remove the need for the pairing feature (WiFi hotspot +
  QR code SSH key exchange) - that's how the phone authenticates to the
  desktop bare repo regardless of which git library does the push/pull.
  Pairing is still unbuilt (see features/pairing/ below, still TODO).

### Vault folder: Synclocal's own, not Working Copy's link trick (corrected 2026-08-08)
Working Copy's role wasn't just git - `openWorkingCopyLinkURL()` in
`ios_app_service.dart` uses Working Copy's own proprietary
`working-copy://x-callback-url/link?repo=X&path=Y` feature, which makes
Working Copy's cloned repo folder *become* the exact folder Obsidian
treats as its vault. That's a Working Copy-only trick, not a generic
iOS capability - initial confusion here led to wrongly assuming
Synclocal would need to reach into an *existing* separate Obsidian
vault folder (via UIDocumentPickerViewController + a security-scoped
bookmark) once Working Copy was removed.

**Corrected direction (user caught this 2026-08-08): Synclocal is a
fully independent app.** It doesn't reach into anything Working Copy
or Obsidian owns. Instead: enable `UIFileSharingEnabled` and
`LSSupportsOpeningDocumentsInPlace` (both `true`) in `ios/Runner/Info.plist`
- standard, documented Apple mechanism since iOS 11, not proprietary to
any third-party app. This exposes Synclocal's own Documents directory
under Files > On My iPhone > Synclocal. `git2dart` clones/pulls straight
into that directory. The user then points Obsidian at *that* folder as
their vault (same "open folder as vault" flow Obsidian already
supports for any folder) - Obsidian adapts to Synclocal's folder, not
the other way around.

**Known caveat to verify on a real device later:** some iOS 18 reports
of the Documents folder not appearing in Files despite both flags set,
particularly on projects that had different settings previously. Not
a dead end, just something to confirm once there's a real build to test.

## Status as of 2026-08-08 (git2dart pivot landed)
- `git_service.dart`: real implementation (clone/fetch/fast-forward-pull/
  push via git2dart), replaces the old Working Copy stub. Compiles clean,
  API verified against the actual package source in `.pub-cache`, not
  just docs. **Not yet run against a live SSH remote** - the real bare
  repo (`Md_files_bare.git`) doesn't exist on the desktop yet either.
- `database_service.dart`: real mobile persistence via `shared_preferences`
  (was a stub that threw on every call - the app would have crashed on
  launch on a real phone before this).
- `Info.plist`: `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`
  added.
- Compile-blocking errors fixed across git_service/ios_app_service/
  vault_service (`StepFailure` API mismatch from an earlier refactor).
- **The hard cases are ported, not deferred anymore:** `sync_service.dart`
  already had every one correctly designed (it's a Dart port of a proven
  desktop script, synco.sh) - conflicts get repaired in place (both
  versions kept, other side quoted in an Obsidian callout, never
  silently lost) rather than aborted, non-fast-forward pushes auto-
  retry after a fetch+fast-forward. The design was never the problem;
  it shelled out to `git`/`ssh` via `Process.run`, impossible on iOS.
  Ported the same logic onto git2dart (`Merge.commit` + repair-on-disk
  + `Commit.create` with both parents; push-retry via fetch+reset+retry).
  `LinkingError.mergeConflict` is now a rare fallback for genuinely
  unexpected failures, not the primary conflict path. `identityNotSet`
  and `rebaseStuck` are now unreachable from this flow (fixed app
  signature, no rebase machinery used) - left in the enum, not deleted.
  Added `ssh_key_paths.dart` for where the phone's own keypair will
  live (Application Support, NOT Documents - that's exposed to Files
  app now, a private key there would be exportable via Files/Finder).
- **`linking_controller.dart` rewritten (2026-08-08), wired to git2dart.**
  Old flow: create empty Obsidian vault -> clone into a Working-Copy-
  managed location -> link Working Copy's repo into the vault path ->
  retry (expected to fail once) -> relaunch Working Copy to clear its
  error banner -> pull. Most of that existed to work around Working
  Copy's own "link" feature quirks. New flow: git2dart clones straight
  into Synclocal's own exposed Documents folder (in-process, no
  external app) -> user opens Obsidian's standard "Open folder as
  vault" pointing at the already-populated folder. Nothing to link -
  the vault folder simply *is* the git-managed folder from the start.
  9 working states -> 4, three park points -> one.
  `ios_app_service.dart`'s Working-Copy-launching methods removed
  (confirmed unused anywhere else first). `linking_screen.dart` barely
  changed - it was already built generically off the controller's
  abstract getters.
- **Pairing built (2026-08-08).** One-time-password flow, not QR+token -
  user's own call when asked directly (avoids a new network-facing
  desktop service). Generates the phone's ed25519 keypair on-device
  (`cryptography` + `openssh_ed25519` for real OpenSSH serialization),
  connects to the desktop with the login password via `dartssh2`
  (never stored), appends the public key to `~/.ssh/authorized_keys` -
  the SSH-equivalent of `ssh-copy-id`. Reachable from a permanent
  AppBar icon and from the linking failure screen's "PAIR NOW" button
  when the error is `pairingNotComplete`.
- **Codemagic build succeeded (2026-08-08) - 2nd ever `.ipa`, not the
  first.** User confirmed a prior build had already produced one before
  today (from an earlier, likely pre-refactor commit - unclear which
  one, not investigated). What's new here specifically: this is the
  first build that includes today's work (git2dart, real persistence,
  pairing, the rewritten linking flow) and the first one built by this
  session. Ran the `ios-release` workflow, branch `main`, unsigned
  `.ipa` artifact produced. This confirms the whole native toolchain
  actually compiles and links for
  iOS - `git2dart` + statically-linked libgit2/libssh2/OpenSSL via
  CocoaPods, `dartssh2`, `openssh_ed25519`, `cryptography` - not just
  `flutter analyze` type-checking. This was the single biggest
  unverified risk from this session's work; it's resolved.
  Codeberg push required generating a new token scoped to this repo -
  the previously stored one only had access to other kworld repos
  (pi5-website/pages etc.), not this one.
- **Still not done:** the `.ipa` is unsigned (`--no-codesign` in
  `codemagic.yaml`) so it can't be installed on a real device yet -
  that needs an Apple Developer account + signing setup, separate from
  today's work.
- **Real device install achieved (2026-08-08) via SideStore/iloader** -
  free Apple ID sideloading, no Mac, no $99/yr Program. `iloader`
  needed `WEBKIT_DISABLE_DMABUF_RENDERER=1` to render on this Pi's
  Wayland compositor. Apple ID sign-in was flaky (bad Anisette
  servers/stale adi.pb) but retrying, resetting adi.pb, and getting
  the 2FA code on-device (Settings -> name -> Sign-In & Security ->
  Get Verification Code, Wi-Fi/cellular briefly off) worked. Once
  `iloader`'s desktop session was signed in, "Import IPA" installed
  the `.ipa` directly - never needed SideStore's on-device sign-in to
  actually work.
- **First real-device run hung on a white screen indefinitely, no
  crash** (confirmed via `idevicesyslog`). Added an on-screen boot
  diagnostic to `main()` instead of guessing blind (release builds
  don't reliably surface print() in device syslog) - it surfaced the
  real error directly: `Failed to lookup symbol 'git_libgit2_init'`,
  a known Dart FFI/iOS issue (dart-lang/native#897) where Release-mode
  dead-code-stripping removes C symbols only referenced via FFI.
  **Fix applied, NOT YET CONFIRMED WORKING:** added `ios/Podfile`
  (didn't exist before) with `-all_load` in `OTHER_LDFLAGS`. First
  rebuild after adding it produced a byte-identical `.ipa` to the
  broken one (7768988 bytes, both build 2 and 3) and hit the same
  error - Codemagic likely reused cached Pods/build state. Added
  `flutter clean` to `codemagic.yaml` before `pub get` to force a
  fresh build - ran out of session time before testing this specific
  build on the real device. **Next session: check if this build's
  file size differs from 7768988** - if still identical, the caching
  issue is deeper than `flutter clean` reaches (maybe Codemagic's own
  cache layer) and needs a different approach (explicit
  `pod install --repo-update`, or check Codemagic's cache settings).
  **Update: flutter clean did NOT fix it either** - same error again
  on the next real-device test. Added a second, distinct fix:
  `STRIP_INSTALLED_PRODUCT = NO` + `DEPLOYMENT_POSTPROCESSING = NO` in
  the Podfile post_install hook. Reasoning: `-all_load` only stops the
  linker dropping whole unreferenced object files *during* linking -
  it doesn't stop Release builds from stripping the symbol table off
  the *final installed binary* afterward, which is what `dlsym()`
  (Dart FFI's runtime lookup) actually reads. These are two separate
  build phases needing two separate fixes. **Not yet tested on a real
  device - ran out of session time.** Next session: rebuild, sideload,
  check if this specific error is finally gone. If it persists even
  after both fixes, the next thing to check is whether git2dart's own
  FFI binding code is even using `DynamicLibrary.process()`/
  `.executable()` (which read the current process's own symbol table)
  versus trying to `DynamicLibrary.open()` a named library that may
  not exist as a separate loadable file when statically linked - that
  would be a git2dart package bug, not fixable from this app's side,
  and would need an upstream issue filed.
  **Update: checked this directly by reading git2dart_binaries' actual
  source (`lib/src/util.dart` in the pub cache) instead of guessing -
  it does use `DynamicLibrary.process()` on iOS, confirming the fix
  category was right.** But `-all_load`/strip settings only modified
  the Pods' own build targets in `post_install` - they didn't address
  that plain `use_frameworks!` (Flutter's default) builds
  `git2dart_binaries` as a **separate dynamic framework**, not merged
  into the main Runner binary, which is what `DynamicLibrary.process()`
  actually needs. Changed to `use_frameworks! :linkage => :static`.
  This is the most confident fix yet, but still **completely untested
  on a real device** - ran out of session time. Next session: rebuild,
  sideload, test. If this specific error is finally gone, revert the
  diagnostic boot screen in `main()` back to the plain version (noted
  in its own comment). If it's still not fixed after this, the
  remaining fallback theory (open a git2dart GitHub issue - this would
  likely be useful upstream regardless, iOS release-mode dlsym failures
  affect anyone using this package for real iOS apps, not just this one).
- **Static linkage fix (above) also failed on a real device (tested
  2026-08-08 evening), same identical error.** Two more attempts
  followed, both since superseded or unconfirmed:
  1. `4692a56` - added `@_silgen_name`-referenced Swift wrapper
     functions for `git_libgit2_init`/`git_libgit2_shutdown` in
     `AppDelegate.swift`, to stop the linker dead-stripping symbols it
     can't see are used (Dart FFI's `dlsym()` lookup is invisible to
     the linker at compile time). Never independently tested - before
     a device run happened, the actual Codemagic build log was read
     directly (not guessed from) and showed a different, more
     fundamental problem.
  2. `4dc544c` - the build log showed `pod install` completing in
     990ms (too fast to be real) and printing "The following plugins
     do not support Swift Package Manager for ios: - git2dart_binaries".
     Read as: Flutter's newer default builds most plugins via SPM
     instead of CocoaPods, and the packaged `.ipa`'s `Frameworks/`
     folder had no framework for git2dart_binaries at all - so none of
     the Podfile-level fixes ever had a chance to apply, because
     CocoaPods was never actually building that plugin. Fix:
     `flutter config --no-enable-swift-package-manager` before
     `flutter pub get`, forcing pure CocoaPods.
  - **Tested on the real device the night of 2026-08-08 (via desktop
    sideload to phone): identical error persisted.** This means either
    the SPM-disable flag didn't take effect for this build, or the SPM
    theory itself was a misread of the log - "plugin does not support
    Swift Package Manager" is Flutter's *normal* per-plugin fallback
    message (it mixes SPM for supported plugins with CocoaPods for
    unsupported ones automatically) and isn't necessarily evidence the
    framework was dropped. Confirmed locally 2026-08-09: no
    `Podfile.lock` or `.flutter-plugins-dependencies` is git-tracked in
    this repo, and `project.pbxproj` has zero SPM package references
    - so there's no stale committed state explaining it either; each
    Codemagic build starts from a genuinely clean checkout.
  - **Decided against guessing a fourth fix blind** (three straight
    guesses have now failed real-device testing, each costing a full
    day-long build+sideload+test cycle). Instead, `codemagic.yaml` gained
    a new "Verify libgit2 is actually embedded" script step, run right
    after the archive build, that greps `Podfile.lock` for `git2dart`,
    lists `Runner.app/Frameworks/`, and runs `otool -L` / `nm` on the
    built `Runner` binary to check directly whether libgit2/libssh2 are
    linked and whether `git_libgit2_init` exists in the binary's symbol
    table. **Next session: read that log output first**, before touching
    any more Podfile/AppDelegate/codemagic.yaml code - it will show
    definitively whether the problem is "framework never got built by
    CocoaPods" (SPM/Podfile config problem) or "framework is present
    but the symbol still isn't reachable at runtime" (a genuinely
    different, deeper problem - possibly a git2dart_binaries packaging
    bug worth an upstream issue).
  - **Result read 2026-08-09: it's neither of those two theories.**
    `Podfile.lock` confirms `git2dart_binaries` WAS resolved and built
    via CocoaPods (ruling out the SPM theory entirely - it was never
    the real problem). But `Runner.app/Frameworks/` has no framework
    for it, `otool -L` shows zero git/ssh2/crypto linkage, and `nm`
    finds no `git_libgit2_init` symbol anywhere in the built binary.
    The pod is resolved but its compiled code never reaches the final
    app at all.
  - **New, better-evidenced theory:** read the actual
    `git2dart_binaries.podspec` from `.pub-cache` (not guessed) - it
    already ships its own precise fix for exactly this class of
    problem: `s.static_framework = true`, vendored `.xcframework`s
    (prebuilt static `libgit2.a`/`libssh2.a`/`libssl.a`/`libcrypto.a`),
    and a `pod_target_xcconfig`/`user_target_xcconfig` with an explicit
    `-force_load "path/to/libgit2.a"` flag - built by the package
    maintainer specifically to survive Release-mode dead-stripping.
    `use_frameworks! :linkage => :static` (added in the earlier static-
    linkage attempt, `6c42abe`) makes CocoaPods build this pod as a
    static-framework-wrapping-a-static-xcframework. This exact nesting
    is a known CocoaPods gap: vendored static xcframeworks inside a
    force-static pod can silently fail to reach the consuming app
    target's real link line, even though `pod install` succeeds and the
    `.xcframework` files are physically present in `Pods/`.
    **Not confirmed - no macOS/Xcode available on this Pi to verify
    directly.** Rather than mutate the Podfile on a fourth blind guess,
    `codemagic.yaml`'s verify step was extended (2026-08-09) to dump
    ground truth instead: `xcodebuild -showBuildSettings` for the
    Runner target's actually-resolved `OTHER_LDFLAGS`, plus the raw
    generated `Pods-Runner.release.xcconfig` and `git2dart_binaries`
    xcconfig contents, to see directly whether the `-force_load` flag
    ever reaches Runner's own target versus staying stuck on the pod's
    own target. **Next session: read that output first.** If the flag
    is present in git2dart_binaries' own xcconfig but absent from
    Pods-Runner's aggregate/Runner's resolved settings, that confirms
    the static-in-static nesting theory - the fix would be either
    dropping `use_frameworks! :linkage => :static` (it may not even be
    needed now that `-force_load` is understood to be the real
    mechanism) or explicitly reasserting `-force_load` on
    `installer.aggregate_targets`' native targets (the actual Runner
    target) rather than only on `installer.pods_project.targets` (the
    pods' own targets) in `post_install`.
  - **Result read 2026-08-09 (second round): static-in-static nesting
    theory refuted.** `xcodebuild -showBuildSettings` for the Runner
    target's Release config shows the fully-resolved `OTHER_LDFLAGS`
    genuinely includes `-force_load` with the correct absolute path to
    `libgit2.a`, plus `-lgit2 -lcrypto -lssh2 -lssl -liconv -lz` and
    `-framework "git2dart_binaries"`. The flag reaches Runner's target
    correctly - `Pods-Runner.release.xcconfig` and
    `git2dart_binaries.release.xcconfig` both have it too. Yet the
    actual compiled binary still has zero trace of any of it (no
    framework, no otool linkage, no symbol). The flag Xcode says it
    will use isn't producing the effect it should - a genuine
    contradiction between the settings Xcode reports and the binary it
    actually produced. Rather than guess why, `codemagic.yaml`'s build
    step now runs `flutter build ipa --verbose`, tee'd to a log file,
    and the verify step greps that REAL build's log directly for
    `force_load` (does it appear in the actual linker invocation, not
    just a post-hoc settings query?) and for `ld: warning`/`ld: error`/
    `duplicate symbol` lines that could explain a forced symbol being
    silently dropped. **Next session: read that output first** - this
    is the third diagnostic round on this exact error, still no
    working real-device build.
  - **Result read 2026-08-09 (third round): found the real gap, real
    fix applied.** The actual raw `Ld` command for Runner (not a
    post-hoc query) confirms `-force_load .../libgit2.xcframework/
    ios-arm64/libgit2.a` genuinely reaches the real link invocation
    with a valid, correctly-resolved path. Combined with the
    `AppDelegate.swift` `@_silgen_name` fix (`4692a56`, confirmed still
    intact and correctly wired: called unconditionally from
    `didFinishLaunchingWithOptions`, gated by a real runtime
    `ProcessInfo` check the compiler can't prove false, so it can't be
    optimized away), the link step should legitimately produce a binary
    containing `git_libgit2_init`. So the gap isn't linking - it's
    afterward. Root cause: `post_install`'s `STRIP_INSTALLED_PRODUCT`/
    `DEPLOYMENT_POSTPROCESSING` = `NO` settings (added in the very first
    fix attempt) were only ever applied via
    `installer.pods_project.targets` - the **Pods project's own
    targets**. They were never applied to **Runner's own target** in
    `Runner.xcodeproj`. Xcode's separate post-link "strip symbols from
    installed product" build phase defaults to on for Release and runs
    against Runner's own (until now untouched) settings - stripping the
    symbol back out after a correct link, which is consistent with
    every piece of evidence gathered (correct resolved flags, correct
    raw Ld command, yet zero trace in the final packaged binary).
    **Fix applied 2026-08-09** in `ios/Podfile`'s `post_install`: added
    a second loop over `installer.aggregate_targets` ->
    `aggregate_target.user_project.native_targets` (the CocoaPods
    idiom for reaching the actual consuming app's own project/target,
    as opposed to `installer.pods_project.targets` which only reaches
    the Pods' own targets) and set `STRIP_INSTALLED_PRODUCT`/
    `DEPLOYMENT_POSTPROCESSING` to `NO` there too, saving the user
    project. **Not yet tested on a real device** - this is the
    highest-confidence fix yet (backed by reading the actual raw
    linker command + the actual generated xcconfig files, not
    Ruby-semantics speculation), but confirm via the existing verify
    step's `nm` check before sideloading: if `git_libgit2_init` finally
    shows up there, sideload and test on the phone. If it's still
    missing, the remaining fallback is checking whether
    `DEPLOYMENT_POSTPROCESSING`/`STRIP_INSTALLED_PRODUCT` alone are
    enough or whether `STRIP_STYLE`/`COPY_PHASE_STRIP` also need
    setting on Runner's target - those are the other Xcode settings
    that can independently trigger symbol stripping.
  - **Confirmed working 2026-08-09: `nm` on the packaged Runner binary
    now finds `git_libgit2_init`/`git_libgit2_shutdown` as real, defined,
    exported symbols** (`T` type, not just an undefined reference).
    First build where the symbol survives into the actual `.ipa`.
    `Frameworks/`/`otool -L` still show nothing, which is expected and
    fine - `-force_load` static-links the code directly into the Runner
    binary rather than as a separate dynamic dependency, so those two
    checks were never going to show anything either way; only `nm` was
    ever the real test here. **Not yet confirmed on a real device** -
    next step is sideloading this specific build and checking whether
    the app gets past the white screen. If it does, revert the
    diagnostic boot screen in `main()` back to the plain version (noted
    in its own comment) and this multi-day debugging arc is closed.
  - **Real-device result 2026-08-09: same error text, but a genuinely
    different failure mode - not the same bug persisting.** Screenshot
    of the boot diagnostic showed the exact runtime error for the first
    time: `Invalid argument(s): Failed to lookup symbol
    'git_libgit2_init': dlsym(RTLD_DEFAULT, git_libgit2_init): symbol
    not found`. Given `nm` had just confirmed the symbol IS compiled
    into the binary, this isn't "missing from the binary" anymore -
    it's that `dlsym(RTLD_DEFAULT, ...)` can't find a symbol that's
    genuinely present. Root cause: on iOS, `dlsym(RTLD_DEFAULT, ...)`
    resolves against each loaded image's **export trie**, not its raw
    `nlist` symbol table. Dylibs get an export trie automatically; the
    **main app executable does not**, by default. `-force_load`/
    `-all_load` only ever controlled whether the code gets linked in -
    a fully separate concern from whether it ends up in the export
    trie afterward, which is what `dlsym(RTLD_DEFAULT, ...)` (what
    `DynamicLibrary.process()` uses under the hood, per git2dart_binaries'
    own source) actually reads.
    **Fix applied 2026-08-09:** added `ios/Runner/
    git2dart_exported_symbols.txt` (wildcard patterns `_git_*` and
    `_giterr_*`, covering the whole libgit2 C API surface rather than
    one symbol at a time) and, in `Podfile`'s `post_install` (the
    `installer.aggregate_targets` loop that reaches Runner's own
    target), added `-exported_symbols_list
    "$(SRCROOT)/Runner/git2dart_exported_symbols.txt"` to Runner's
    `OTHER_LDFLAGS`, explicitly telling the linker to add those symbols
    to Runner's export trie. **Not yet tested on a real device.**
    Risk to watch: `-exported_symbols_list` restricts a target's export
    trie to *only* the listed symbols by default - for a plain app
    main executable with no extensions/no other image dynamically
    loading into it, this should be safe, but if some other unrelated
    dlsym(RTLD_DEFAULT) call elsewhere in the app (Flutter engine,
    another plugin) unexpectedly relied on a symbol NOT matching
    `_git_*`/`_giterr_*` previously being exported by default, this
    could introduce a new, different failure. Watch for a different
    "Failed to lookup symbol" error naming something other than a
    libgit2 function if this happens.
  - **CONFIRMED FIXED 2026-08-09.** Real device now boots straight to
    the actual app UI: "synclocal / No repositories / SET UP VAULT".
    No crash, no white screen. This closes the entire
    `git_libgit2_init` debugging arc (four real-device test cycles
    across 2026-08-08 and 2026-08-09: static framework linkage ->
    SPM/CocoaPods -> Runner-target strip settings -> export trie
    visibility - each one a genuinely different bug in a different
    part of the pipeline, not the same guess repeated). Reverted the
    diagnostic boot screen in `main()` back to the plain
    `async main() { ... runApp(SynclocalApp(...)) }` per the plan
    noted in its own comment - `_BootScreen`/`_BootScreenState` are
    gone, `PlatformSpecific.initialize()` and
    `getApplicationDocumentsDirectory()` now just run inline before
    `runApp`. Left `AppDelegate.swift`'s `@_silgen_name` symbol
    retention hack in place - not verified redundant now that the
    export-trie fix works, and it's cheap to keep since it's
    plausibly still needed for the link-time `-dead_strip` survival
    concern, which is a different pipeline stage than the export-trie
    fix addressed.
  - **Next up:** the app has never actually pushed/pulled against a
    real bare repo yet (`git_service.dart`'s git2dart implementation
    was compiled-clean and API-verified but never run against a live
    SSH remote - the bare repo `Md_files_bare.git` may not even exist
    on the desktop yet, see earlier status note). Now that the app
    genuinely boots, that's the next real gap to close before this is
    close to shippable, along with the still-fully-unbuilt settings
    feature and the user's list of real Working Copy/sync errors
    (below) still not handed over.
- The user has a list of real Working Copy/sync errors from actual
  usage history, still not yet handed over - see the note earlier in
  this doc about slotting those into `LinkingError` when it arrives.
- **User has a list of real Working Copy / sync errors from actual
  usage history, not yet handed over (2026-08-08).** The state machine
  is deliberately step-based with a single `LinkingError` enum so that
  list can be absorbed as additional error cases slotted into the
  existing steps later, without needing another architectural rewrite.
  When it arrives: map each real error to the step it actually happens
  in, add a `LinkingError` case + diagnosis/resolution text, don't
  restructure `LinkingStep` unless a case genuinely doesn't fit any
  existing step.

### Status as of 2026-08-09: first full real end-to-end success
Pairing -> clone -> Obsidian vault open -> complete all worked together
on a real device for the first time this session, after the
`git_libgit2_init` crash (above) was resolved. Getting from "app boots"
to "actually works" took a real chain of distinct bugs, each found by
reading actual on-device evidence rather than guessing - same
discipline as the crash debugging:
- **Config drift, not code bugs**: `bareRepoPath` and `desktopIp` were
  hardcoded wrong (stale/never-correct) in 8 separate places across the
  codebase - none shared from one source. Real bare repo path is
  `Git/pi5-obsidian/Git_bare_repo/Md_files_bare.git` (confirmed via the
  desktop's actual `Obsidian_vault` git remote). `desktopIp` needs
  re-checking **every session** - it's the desktop's current
  hotspot-subnet IP, and there's no settings screen yet to configure it
  on-device. Also caught: the desktop has two simultaneous interfaces
  in that same address range (USB tethering via `eth1`/`ipheth`, and an
  unrelated WiFi network on `wlan0` that coincidentally overlaps Apple's
  hotspot subnet) - `ip -d link show` + `lsusb` are how to tell them
  apart, not just `ip addr show`.
- **libgit2 has no `known_hosts` on iOS**: `git_service.dart`'s
  `Callbacks` never set `certificateCheck`, so every SSH connection was
  rejected with `GIT_ERROR_SSH: invalid or unknown remote ssh hostkey`
  regardless of credentials. Fixed by accepting unconditionally -
  reasonable given trust is already established via the password-based
  pairing step, not a general-purpose SSH client reaching arbitrary
  hosts.
- **Swallowed exceptions hid all of the above**: both
  `pairing_controller.dart` and `git_service.dart` had catch blocks
  that mapped every unrecognized exception to the same generic
  `connectionRefused`/`refused` message (some via `const StepFailure`,
  which can't even carry the caught exception). Added an optional
  `debugDetail` field to `StepFailure`, populated with `e.toString()`
  and shown on both the pairing and linking failure screens - this is
  what actually made each subsequent fix possible instead of another
  round of guessing. Also added real `_diagnose()` classification to
  `git_service.dart` (mirroring `pairing_controller.dart`'s) so auth
  failures show the right diagnosis/resolution/PAIR NOW button instead
  of "check your network" dead ends.
- **iOS blocks `canLaunchUrl` for unlisted schemes**: `obsidian://`
  reported "not installed" even when installed, because
  `LSApplicationQueriesSchemes` was entirely absent from `Info.plist`.
- **Sequencing bug lost the user mid-flow**: `_openObsidianForVaultPick()`
  called `launchUrl()` (backgrounding Synclocal) *before* setting the
  parked step and notifying - the "here's what to do in Obsidian, then
  come back" instructions never got a chance to render. Now shows
  instructions first with a deliberate `OPEN OBSIDIAN` button.
- **Completion didn't persist anything**: reaching `LinkingStep.complete`
  never called the already-existing `RepositoryProvider.addRepository()`
  - a fully successful link still left the home screen showing "No
  repositories". Now inserted on arrival at the complete screen.
- **UX**: pairing success was a single 14px teal line, easy to miss
  entirely under stress - replaced with a full-screen success state and
  one obvious next action. Several error/instruction text sizes were
  bumped up after being flagged as too small to read comfortably.

### Status as of 2026-08-09 (later same day): sync had never actually worked
After the end-to-end success above, testing the *ongoing* sync path
(not just initial setup) surfaced the most serious bug found this
session: `SyncService.fromRepo()` used `repo.obsidianVaultPath` (a
cosmetic Files-app display label like `"On My iPhone/Synclocal"`) as
the real filesystem path for git operations. That string can never
resolve to a real directory, so `fullSync()`'s very first check
(`Directory('$vaultPath/.git').exists()`) always failed, immediately
returning `bareRepoNotFound` - **every sync attempt, ever, regardless
of network state.** This had nothing to do with the desktop being
unreachable; it would have failed identically fully wired up on the
same WiFi network. Root cause: `Repository` never had a field for the
real on-disk path at all, only remote (desktop) fields and the cosmetic
display label.

**Fix**: added `Repository.localPath` (same value
`LinkingController`/`GitServiceImpl` already used correctly for the
*initial* clone - `getApplicationDocumentsDirectory().path`), wired
through both the automatic linking flow and the manual Add Repository
form. `SyncService.fromRepo()` now uses `repo.localPath`. Old
locally-persisted repo records predate this field and needed
removing + re-adding via Set up a vault - not a data-loss risk, they
never actually worked anyway.

**Also fixed same day**: `_verifySync()` was a literal no-op -
unconditionally reported success regardless of whether the user did
anything in Obsidian, confirmed on a real device (user backgrounded
Obsidian without touching it, switched back, got "You're all set!").
Added the one check Synclocal can genuinely make from its own sandbox
(did the download actually produce files locally - `.git` dir exists,
folder non-empty) via a new `LinkingError.cloneVerificationFailed`
case. **Cannot** verify the Obsidian-side step (folder opened as a
vault there) - no cross-app introspection on iOS - and the resolution
text says so honestly rather than pretending otherwise.

**UX, same session**: two unlabeled app-bar icons (key/phone, tooltip-
only which doesn't show on tap on iOS) consolidated into one menu with
real text labels. Repo-tile and dialog text sizes bumped again
(10-14px -> 12-17px) after repeated real-device "too small" feedback -
this has now happened enough times across enough screens that any
*new* screen should default to ~14-16px body text from the start
rather than iterating up from ~10-12px each time.

### Important architectural finding: iOS container paths are not stable (2026-08-09)
The first attempt at the `localPath` fix only repaired records with an
*empty* path (from before the field existed). Real-device testing then
surfaced a deeper problem via the same `debugDetail` plumbing: a
genuinely different, non-empty, previously-valid path still failed -
`GIT_ERROR_OS: failed to make directory '.../4642BD76-.../': Operation
not permitted`. Root cause: `getApplicationDocumentsDirectory()`'s
underlying container UUID **changes on every app reinstall**, which
happens on every rebuild+resideload during development (each new
`.ipa` install is not a same-container update the way a normal App
Store update would be). A path cached from a previous launch can point
at an orphaned container the current process's sandbox has no access
to - EPERM, not ENOENT, since the path may still exist at the
filesystem level generally, just outside this process's MAC profile.

**Fix**: `RepositoryProvider._refreshLocalPaths()` now unconditionally
recomputes and re-persists the live container path on every launch
(not just when empty), plus defensively again at the top of
`syncRepository()` itself.

**General rule for this codebase going forward**: never persist an
absolute `getApplicationDocumentsDirectory()`-derived path and trust it
later - always recompute it live at the point of use. This app has
exactly one real local vault folder, so there's no cost to doing that
every time. Any *new* code that touches local file paths should follow
this from the start rather than needing the same bug found twice.

**Next real gaps**: `pushToBareRepo()` (phone -> desktop direction) is
still completely untested - only the pull/clone direction has run for
real, and only just started working at all today. Settings feature
(would fix the hardcoded-IP problem) and the user's list of real
Working Copy/sync errors (below) are both still outstanding.

### Major architecture correction: Obsidian owns the vault folder, not Synclocal (2026-08-09)
Everything above this point in the doc describes the *previous*
architecture: Synclocal clones into its own private Documents folder,
then the user is told to "open folder as vault" in Obsidian to point
at it. **That direction was wrong**, and it's why full end-to-end
completion kept reporting success without the user ever actually
having a working Obsidian vault.

Root cause found by asking the user for their own hard-won
documentation (years of real Working Copy + Obsidian iOS usage,
described by the user as "secret sauce" they'd already solved through
real pain - the correct move was to stop guessing/web-searching and
work directly from that) rather than continuing to guess at Obsidian's
iOS UI from training-data memory. Two concrete confirmations:
- The user's own real Obsidian 1.12.4 "Manage vaults..." screen has no
  "Open folder as vault" option at all - only "Create new vault"
  (which makes a brand-new empty vault, optionally in iCloud) and a
  list of existing vaults. This had been assumed/guessed wrong this
  whole session.
- The user's own Working Copy setup notes (`#### 13. Link Working Copy
  to Obsidian Vault`) show the real, working direction: create the
  vault in Obsidian FIRST ("Create a vault -> Continue without sync ->
  name it -> Create a vault", on-device, not iCloud - this makes
  `On My iPhone/Obsidian/<name>`), THEN the sync tool (Working Copy)
  requests access to that already-existing folder via "Link Repository
  to -> Directory -> navigate to On My iPhone -> Obsidian -> <vault
  name>". iOS's cross-app folder access for this requires a real
  security-scoped bookmark (`startAccessingSecurityScopedResource()`/
  `stopAccessingSecurityScopedResource()`, matched 1:1 around every
  use) - a plain path string silently loses access, the same general
  class of problem as the container-path-instability finding above,
  just for a different underlying reason (permission scope, not
  container identity).

**What changed** (full detail in the `e83ee9a` commit message):
- `ios/Runner/AppDelegate.swift` gained `VaultFolderChannel`: a
  `FlutterMethodChannel` bridging to `UIDocumentPickerViewController`
  (string-UTI `"public.folder"` form, not the newer `UTType`-based API,
  specifically to avoid raising this project's iOS 13.0 deployment
  target) plus security-scoped bookmark create/resolve.
- New `lib/services/vault_folder_service.dart` wraps the channel from
  Dart: `pickFolder()`, `startAccessing(bookmark)`,
  `stopAccessing(bookmark)`.
- `Repository` gained `vaultBookmark` (base64) - `localPath` alone
  can't retain cross-app access across launches.
- `LinkingController` flow reordered: `checkingPairing` ->
  `awaitingVaultCreation` (user creates the vault in Obsidian, "OPEN
  OBSIDIAN" button) -> `pickingVaultFolder` (native picker,
  "SELECT VAULT FOLDER" button) -> `cloning` (into the picked folder)
  -> `verifySync` -> `complete`. The old `awaitingObsidianVaultOpen`
  step (clone first, ask Obsidian to open the result second) is gone.
- `GitServiceImpl.pullFromBareRepo()` and `SyncService`'s clone-
  recovery path both changed from `Repository.clone()` (requires an
  empty target directory) to `Repository.init()` + fetch + hard reset
  - the target folder now always has Obsidian's own `.obsidian/`
  config dir already in it from vault creation, exactly mirroring what
  real `git init && git remote add && git fetch && git reset --hard`
  does on a non-empty fresh directory. Hard reset force-overwrites
  Obsidian's placeholder content, which is fine since the vault was
  just created moments ago with nothing real in it yet.
- `SyncService.fullSync()` now resolves fresh bookmark access at the
  start of every sync and releases it at the end - never trusts a
  cached path for the actual git operations.
- `RepositoryProvider._refreshLocalPaths()` (the fix from the
  container-path-instability finding above) removed entirely - it
  existed specifically to work around Synclocal's own container path
  going stale across reinstalls, which doesn't apply once the vault
  folder lives in Obsidian's own stable storage instead.
- `add_repository_screen.dart`'s manual "Add Repository" form now uses
  the same real folder picker instead of computing
  `getApplicationDocumentsDirectory()` - the same wrong assumption,
  would have produced the same class of broken record.

**Verified via `flutter analyze`** before pushing (Flutter SDK is
installed on this Pi as of 2026-08-08) - caught and fixed two real
compile errors (a dropped `ChangeNotifier` import, a stale
`test/widget_test.dart` reference) that would otherwise have only
surfaced as a failed Codemagic build. Native Swift side and the actual
document-picker/bookmark flow are **completely untested on a real
device** - this is the single biggest unverified risk in the codebase
right now, bigger than anything above. Next session: build, sideload,
and run the full "Set up a vault" flow for real, checking specifically
whether `VaultFolderChannel` registers correctly (risk: the implicit-
engine `FlutterViewController` may not be synchronously available in
`application(_:didFinishLaunchingWithOptions:)` the way the code
assumes) and whether the picker/bookmark round-trip actually works.

### URL schemes used
- working-copy://x-callback-url/link?repo=NAME&path=VAULT
- working-copy://x-callback-url/pull?repo=NAME
- working-copy://                          (open app - dead, Working
  Copy was removed in the git2dart pivot; kept here as a historical
  note, not a live reference)
- obsidian://                              (open app)
- obsidian://new-vault?name=NAME           (Phase 2)

### Protected IP
The 8-step sequence and error resolution strings live in:
- linking_state.dart (LinkingError.resolution)
- linking_controller.dart (step logic)

These are the core value of synclocal. Keep them out of any
open-source release.
```
