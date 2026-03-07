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

### Git library: none (for MVP)
- dart-git: push/pull unimplemented, abandoned 2022
- libgit2 FFI: viable but App Store entitlements for .dylib are complex
- Decision: delegate all on-device git ops to Working Copy via URL scheme
  for MVP. Working Copy is a precondition of the whole workflow anyway.
  Phase 2: evaluate libgit2 FFI once core flow is proven.

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
