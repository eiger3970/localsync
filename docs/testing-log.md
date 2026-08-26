# Real-device testing log

Findings from live, on-device testing - symptom, root cause, and what actually
happened about it. Kept separate from the inline `// 2026-08-26: real
feedback, live - ...` comments scattered through the code (those stay as the
detailed record at the exact line they affect) - this is the consolidated,
skimmable version: what broke, why, and whether it's fixed or still open.

## 2026-08-26

### Fixed this session

**Password field sparkle was static, then not random.** Two `Icon` widgets
with no animation at all → given a real sine-wave twinkle → still read as a
predictable seesaw (one shared controller, fixed phase offset put the two
stars in perfect antiphase, and every field instance mirrored every other).
Fixed with two independent-period `AnimationController`s plus a per-instance
random start phase (`shredding_password_field.dart`). Position needed several
rounds of tuning (`Transform.translate` offset, currently 16) - repeatedly
under-corrected on the first few attempts because top-padding on a
`prefixIcon` gets partially cancelled by Flutter's own centering.

**Password retry list had two different implementations that drifted.**
`pairing_screen.dart` never got the 10-message escalating list at all - only
`linking_screen.dart` did. Extracted into one shared function
(`passwordRetryMessage` in `linking_state.dart`) both screens call. Also
widened from `connectionRefused`-only to also cover
`pairingPasswordRejected` (`isPasswordRetryError`) - a wrong password can
surface as either LinkingError depending on how the desktop's SSH server
behaves on a failed attempt, a distinction already documented in this app's
own error-diagnosis history. List content reordered per direct request
("uninstall and reinstall the app" moved from #3 to #10, last resort not an
early suggestion).

**Vault-link merge conflict just failed instead of merging.** Linking an
already-used real vault folder (existing git history) hit
`LinkingError.mergeConflict` and stopped outright - a deliberate 2026-08-08
scope cut, never revisited. `git_service.dart`'s `pullFromBareRepo()` now
reuses the same three-way-merge-and-repair pipeline `sync_service.dart`'s
day-to-day pulls already use (commit dirty tree first, merge, repair
conflicts in place, both sides kept). Side effect: also fixed a real latent
data-loss risk - the fast-forward path used to hard-reset with no safety
commit first, which could have silently discarded uncommitted real notes.

**"Kept for reference" conflict callout read as an active, alarming error.**
Wording was "Also in desktop obsidian's version (edit in, or delete)" - a
real user hit this and asked "is this an Obsidian error, unfixable from the
app?" It's neither - it's LocalSync's own already-resolved leftover, by
design excluded from the Conflicts scanner. Reworded to say so directly:
"Already resolved - kept for reference only, not an active conflict."
**Important limitation**: this only changes wording for *newly written*
callouts. Text already sitting in existing notes keeps the old wording
forever - there's no in-app rewrite-old-callouts feature. The real, repeatable
fix for a user with no terminal access: open the note in Obsidian and
hand-edit or delete the block, same as editing any other text.

**Conflicts screen guidance was hidden, then contextually broken.** The
push-to-sync step lived only behind an info-icon dialog - real testing needed
to ask directly rather than find it there. Made into an always-visible
banner - which then showed "pick a version below" even with zero conflicts
below to pick ("Conflicts screen makes no sense now"). Split into two states:
the banner only appears alongside real entries; the empty state keeps a push
reminder without the nonsensical instruction.

**Conflicts screen scan had no loading text.** Bare spinner read as
unclear/stuck. Added "Scanning your entire phone PKM vault…" under it.

**First SSH connect attempt failed even with the correct password.**
`SocketException: ... No route to host, errno = 65` on the very first
pairing attempt; the identical correct password worked immediately on retry
against the same IP. Not a real, sustained unreachability - a route/ARP
condition not ready yet right after a network change (hotspot reconnect, app
resume). Added one bounded automatic retry in `pairing_controller.dart` on
`SocketException` specifically, so the user doesn't have to manually retry.

**Push showed a raw internal debug dump as its result message.** "Nothing to
sync - path=/private/var/...bla bla bla" filled the whole screen. Root cause:
a `SyncNoChanges.debug` field added 2026-08-14 as a *temporary* diagnostic
("remove once the root cause is found and fixed") for a real bug where a
genuinely new note wasn't detected as a change - that root cause was fixed
(`commitDirtyTree`'s always-stage-and-compare-tree-hash approach) but the
diagnostic dump itself was never removed, so it kept firing on every
completely normal "nothing to push" case. Removed the field and the dump
entirely; `syncResultMessage()` now always returns a plain "Nothing to
sync."

### Known, real, not fixed today

**No desktop-side app component.** The desktop's own Obsidian vault only
stays in sync with the bare repo because of `synco.sh`, a script this user
already had for their own Raspberry Pi setup - not something LocalSync ships
or manages, and not something a real customer would have waiting for them.
Worth a deliberate decision: does LocalSync need its own desktop counterpart,
or does it stay phone-only with the desktop side left to the user's own
tooling?

**Obsidian's iOS file cache doesn't always notice a background pull.**
`coordinatedWrite` (the fix for this exact class of problem) is only used by
the manual conflict-picker resolution path (`conflict_scanner.dart`). Every
pull/merge writes files through git2dart's native checkout instead, which
bypasses it entirely - so a file updated by a pull can still show stale
content in Obsidian until the app is force-closed and reopened. Retrofitting
`coordinatedWrite` across the whole pull/merge pipeline is a bigger job
(libgit2 does that file I/O natively, not through Dart writes that can be
easily rerouted) - flagged, not attempted yet.
