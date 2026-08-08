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
  today's work. Nothing has run against a real SSH connection or been
  used on an actual phone. The user has a list of real Working
  Copy/sync errors from actual usage history, still not yet handed
  over - see the note earlier in this doc about slotting those into
  `LinkingError` when it arrives.
- **User has a list of real Working Copy / sync errors from actual
  usage history, not yet handed over (2026-08-08).** The state machine
  is deliberately step-based with a single `LinkingError` enum so that
  list can be absorbed as additional error cases slotted into the
  existing steps later, without needing another architectural rewrite.
  When it arrives: map each real error to the step it actually happens
  in, add a `LinkingError` case + diagnosis/resolution text, don't
  restructure `LinkingStep` unless a case genuinely doesn't fit any
  existing step.

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
