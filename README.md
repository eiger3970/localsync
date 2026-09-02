# LocalSync

Local-first sync for your Obsidian vault, directly between your iPhone and
your own desktop - no cloud, no subscription, no third party ever sees your
notes.

- **Website:** https://kworld.space/localsync
- **Get the app:** search "LocalSync" on the App Store (iPhone only for now)
- **Desktop setup file / one-line install:** https://kworld.space/localsync

## What this repo is

This is LocalSync's source - the Flutter/iOS app, plus the desktop setup
scripts under `desktop/` that the app and the website both point people to.
If you just want to install and use LocalSync, you don't need anything in
this repo directly - use the website link above.

This repo is useful if you want to:

- Verify what `desktop/setup.sh` actually does before running it
- Read or audit the source
- Report a bug or request a feature

[Codeberg](https://codeberg.org/kworld/localsync) is the canonical
repository - this GitHub copy is a mirror, kept in sync automatically, used
for CI (the App Store build pipeline needs a macOS runner).

## Desktop setup

See [docs/desktop-setup.md](docs/desktop-setup.md) for the full guide - git,
SSH, and auto-discovery, covered by one terminal command or a double-click
file for Mac/Linux.

## Support

Open an issue at https://codeberg.org/kworld/localsync/issues.

## License

Not yet set - a real license file is still an open item, not a deliberate
choice to withhold one.
