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

### URL schemes used
- working-copy://x-callback-url/link?repo=NAME&path=VAULT
- working-copy://x-callback-url/pull?repo=NAME
- working-copy://                          (open app)
- obsidian://                              (open app)
- obsidian://new-vault?name=NAME           (Phase 2)

### Protected IP
The 8-step sequence and error resolution strings live in:
- linking_state.dart (LinkingError.resolution)
- linking_controller.dart (step logic)

These are the core value of synclocal. Keep them out of any
open-source release.
```
