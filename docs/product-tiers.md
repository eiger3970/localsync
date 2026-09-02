# LocalSync - product tier outline

Written 2026-08-26, same session as the free/paid boundary redraw (see
`pricing-tiers.md`'s superseded notice and `Projects/LocalSync.md`'s
"Pricing ladder, 2026-08-26 second refinement"). This is the functional
tier ladder specifically - separate axis from the skins bundle/
enterprise/anti-buyout tiers already in `Projects/LocalSync.md`'s
pricing ladder diagram, which still apply on top of this.

## Tier 0 - Free: File Sync

- **Target user, user's own framing**: "normies" trying local sync for
  the first time - basic non-binary (text) notes/diary use is the
  headline appeal, not a full binary-file power-user pitch. Real
  value: **no Terminal, no Git, no rsync knowledge required** - those
  are powerful FOSS tools, but the UX gap between "powerful CLI tool"
  and "something a normal person can actually use" is the product.
- **Desktop reach - already true, no new code**: the desktop side has
  never been a custom app, just "a machine reachable over SSH with git
  installed and a bare repo" - true out of the box on Linux and Mac,
  and on Windows via Git for Windows (OpenSSH is now built into Windows
  10/11) or WSL. LocalSync's phone side is protocol-level (SSH+git),
  not OS-specific - "syncs to Linux, Mac, or Windows" is a real claim
  from day one, not aspirational.
- **What**: generic file sync between the user's own phone and desktop.
  User picks a folder on each side (not a fixed "always your whole
  Documents folder" - see the "pick a folder" decision from this
  session).
- **Files**: any - binary and/or non-binary, no content awareness of
  any kind.
- **Mechanism**: the existing git2dart-based sync engine, unchanged
  (verified: the core clone/commit/push/pull/merge path has no
  Obsidian-specific logic in it at all - confirmed by direct
  investigation this session). Not literally the `rsync` binary, but
  rsync-equivalent behavior from the user's point of view - both sides
  converge, changes propagate.
- **Conflicts**: whole-file only - "keep yours or keep theirs." No
  text-aware merging, no diff view. Simpler than every PKM tier below,
  not a lesser version of them.
- **PKM awareness**: none. No Obsidian vault linking, no
  markdown/Kanban-aware conflict repair.
- **Status**: not built yet. Scoped this session - new linking path
  (skip the Obsidian-specific `awaitingVaultCreation` step, reuse SSH
  pairing/device-discovery/clone/push/pull as-is), plus a generic
  whole-file conflict-pick UI.

## Tier 1 (IAP) - PKM Sync: Text

- **What**: Obsidian-vault-aware sync - the full researched
  vault-linking sequence (8-step pairing, the "New tab"/force-close
  vault-creation recipe, security-scoped bookmark folder access).
- **Conflicts**: manual, raw markdown text - today's actual built
  behavior. Real merge-in-file safety net (the chosen version stays in
  the note, every other version gets folded in as a reference callout,
  nothing silently dropped), Kanban-safe.
- **This is the app's entire current free-tier experience**, moved
  behind this paywall per this session's business-model redraw. Not new
  code - already built and real-device tested across many prior
  sessions.

## Tier 2 (IAP) - PKM Sync: Visual (manual pick)

- **What**: same PKM-aware sync as Tier 1, plus a visual side-by-side
  conflict picker (word-level diff highlighting, vimdiff-style) instead
  of reading raw markdown.
- **Conflicts**: still manual - tap to keep one whole side. Easier to
  read, not a different resolution model than Tier 1.
- **Already built**: `conflict_picker_screen.dart`'s `useDiff`/vimdiff
  view. Currently ungated (free during testing) - the code exists, just
  not wired to a real purchase check yet (no funded App Store product).

## Tier 3 (IAP premium) - PKM Sync: Visual + Automatic Merge

- **What**: same as Tier 2, plus automatic sentence-level put/yank
  merge - compose a result from *both* sides piece by piece, not just
  pick one whole side. Real vimdiff `dp`/`do` is the design reference.
- **Already built today**: `merge_picker_screen.dart` +
  `line_diff.dart`. Currently ungated (free during testing), same
  reason as Tier 2.

## Later: other PKMs

LogSeq, Notion, Joplin, Tana, etc. layer onto Tiers 1-3 once Obsidian
support is proven and selling - per the existing "per-PKM paid unlock"
idea in `Projects/LocalSync.md` ("New IAP idea - other PKM support").
Not scoped further than that idea yet - each one is its own real
integration (different file format/conflict shape per app), not a
toggle on the existing Obsidian code.

## Pricing - realistic maximums, worked out 2026-08-26, revised same day

**Working Copy corrected, second pass - it's not a PKM comparable at
all.** User's own words: "Working Copy is not designed for PKMs, just
git device to device. To connect to PKM is very tricky, including
paying for a special linking release feature and then manually
figuring out on your own how to connect Working Copy to the PKM. So
difficult that near 0 can do it or use it for that." This removes
Working Copy as a price *floor* for the PKM tiers entirely - it was
never a real alternative for the actual job LocalSync does (this
matches `[[project_synclocal_vault_recipe]]`'s own "years of real
pain" research into exactly this gap). **Net effect: more headroom on
Tiers 2-4 than the first pass gave credit for, not less** - there is
effectively no accessible competing product for "PKM-aware local sync
a normal person can actually set up," at any price.

The remaining real anchor is unchanged and doesn't depend on Working
Copy at all: price near one year's worth of Obsidian Sync ($4-8/month
= **$48-96/year**), charged once, for life - that's the ceiling before
"why not just pay monthly and cancel anytime" starts winning the
argument against a one-time purchase.

| Tier | Realistic max (one-time, incremental) | Reasoning |
|---|---|---|
| 1. File Sync | $0 | Acquisition funnel, not revenue |
| 2. PKM Text | **$24.99** | No accessible competing product exists at any price - Working Copy's PKM path is real but "near 0 can do it." Launch-low price, not a ceiling - see headroom note above |
| 3. PKM Visual (manual) | **+$14.99** (-> $39.99 combined w/ Tier 2) | Same capability as Tier 2, easier UX - an increment, not a new capability |
| 4. PKM Visual + Auto (premium) | **+$19.99-24.99** (-> **$59.99-64.99 for the full Obsidian stack**) | No competitor does automatic PKM-aware merge at all - most pricing power here, capped near one year of Obsidian Sync so it still reads as a steal against paying forever |
| 5. Everything bundle (all PKMs) | **$99-149** (already in `Projects/LocalSync.md`'s pricing ladder) | Cross-PKM (Obsidian + LogSeq + Notion + Joplin + Tana...), priced above the sum of individually-priced PKM tiers - the actual anti-cheap-backdoor ceiling |

This ceiling (~$60-65 for the complete Obsidian tier stack) sits under
row 5's cross-PKM bundle - a bigger purchase than one PKM's full stack,
so the numbers stack correctly rather than colliding.

## Launch strategy: these are ceilings to grow into, not day-one prices

Easier to raise prices for new buyers later (grandfather existing
buyers at their purchase price - standard, doesn't read as a
bait-and-switch) than to launch high and either alienate early adopters
or have to walk a price back. Also the more FOSS/Linux-community-
respectful path - earn the higher price once quality is demonstrated
with real usage and reviews, don't extract maximum value from people
trusting an unproven product on day one.

**Recommendation: launch each tier near the low end of its range,
raise for new purchasers only as the product proves itself** - matches
the existing pattern of shipping low ("$19.99... raise once polished")
and applying it consistently across every tier above, not just the one
that already had it. Grandfather every early buyer at their purchase
price when a later raise happens - that's how the ceiling gets reached
without upsetting anyone who bought in early.

## Resolving "mass market" vs. "high price" - the tier split IS the answer

User's own tension, stated directly: wants mass-market reach ("breaking
the cloud storage controls with easy normie ux") *and* a high enough
price to not undervalue something genuinely differentiated. These
aren't actually in conflict once Tier 0 exists - **Tier 0 (free, $0)
is what captures mass-market reach and normie goodwill; Tiers 2-4
capture value from the users who need the harder PKM capability.**
The free tier doesn't need to be cheap-and-cheerful to subsidize a
low-priced paid tier - it's genuinely free, and the paid tiers can hold
a premium price precisely *because* the free tier already did the
mass-market job. Trying to make one single price point serve both
goals is what creates the tension; splitting them into a real free
tier plus a premium paid tier removes it.

## Honest note on defending against copycats - grandfathering isn't that

User's own concern: competitors will build cheaper apps once LocalSync
proves the market exists, and wants to "keep the 1st customers with my
original pioneering app for longevity." **Grandfathering protects
retention of existing customers - it does not, by itself, stop a new
customer from choosing a cheaper competitor instead of LocalSync.**
Worth being precise about the difference, not conflating the two:

- **What actually defends against being undercut**: the vault-linking
  automation itself is a real technical moat - a copycat has to redo
  the same multi-day, multi-session research this app's own history
  represents (see `[[project_synclocal_vault_recipe]]`, the iOS
  security-scoped-bookmark/export-trie debugging saga earlier in
  `[[project_synclocal_app]]`) before they can even match feature
  parity, not just undercut on price. First-mover brand trust, reviews,
  and continued feature velocity (staying ahead, not just staying
  first) are the other real levers - not the price itself.
- **What grandfathering actually buys**: loyalty and reduced churn
  among people who already bought in, and a genuine "thank you for
  believing early" story worth telling publicly - real value, just a
  different kind of protection than a moat against new customers
  picking a cheaper alternative.

## Positioning - unique seller, confirmed against the competitor table

Every competitor already logged in `Projects/LocalSync.md` fails at
least one of "local-first" or "PKM-aware and actually usable":
Obsidian Sync is PKM-native but cloud/subscription; Working Copy is
local-first but PKM-connection is real yet practically inaccessible
("near 0 can do it"); Syncthing/KDE Connect/Self-hosted LiveSync are
local-first but have zero PKM awareness at all. **Nothing on that list
is both local-first and genuinely usable by a normal person for PKM
sync - that gap is the actual product**, not a marketing angle bolted
onto an otherwise-ordinary sync app.

## New idea, captured not scoped: side-app market segmentation

User's own framing: digitizing diaries opens a real, distinct field
beyond "sync app for PKM power users" - the same core local-sync engine
could support separately-branded/positioned products for different
audiences, each with its own UX and messaging, not one app trying to
speak to all of them at once:

- **Kids' diaries** - a child writes privately on their own device; a
  parent can see it on their own desktop/phone (explicitly framed as a
  safety/care feature, not surveillance for its own sake) via the same
  local sync mechanism, with no cloud exposure of a child's private
  writing to any third party.
- **Authors needing privacy** - manuscript/notes sync between a
  writer's own devices without cloud exposure risk (leaks, third-party
  access to unpublished work).
- **Frugal, non-technical parents** - "just wanting to save a dollar
  with no computer experience" - the mass-market Tier 0 audience,
  named explicitly as its own segment rather than folded into "PKM
  users" generically.

Not scoped, not started - captured here so it isn't lost, same
treatment as the qrcp idea below. Real strategic question if this is
pursued later: one app with audience-specific onboarding flows, or
genuinely separate apps sharing the same sync engine - not decided,
don't assume either direction.

## Long-term thread, captured not scoped: peer-to-peer/disintermediation as an asset

User's own framing: LocalSync's device1<->device2, no-server-in-between
pattern is "kind of peer2peer," and may lead toward other interests -
named example, "blockchain administration with permanent logs and
disintermediation."

**Technical precision worth keeping, not just agreeing with the
parallel**: git's own commit history is already hash-chained and
tamper-evident (each commit cryptographically references its parent,
can't be silently rewritten without it showing) - genuinely
blockchain-*adjacent* in spirit. It is not a blockchain technically -
no distributed consensus, no proof-of-work/stake, no mechanism for
mutually-*untrusting* parties to agree on shared state. LocalSync gives
"permanent, tamper-evident, disintermediated log between two devices
the same person controls" - real blockchain administration is a
different problem (consensus among parties who don't trust each
other), not a bigger version of this.

**The real throughline is the pattern, not the specific tech**:
genuine, tested expertise in peer-to-peer/disintermediated sync
architecture - no server in the middle, user holds the data,
tamper-evident history - is a transferable asset toward whatever comes
next in that direction, even though a real distributed-trust product
would need a different implementation. Not scoped, not started -
captured so the thread isn't lost.

## Adjacent idea, captured not scoped: qrcp-style ad-hoc transfer

User flagged `github.com/claudiodangelis/qrcp` (QR-code-based one-off
file transfer over local network, no app install, no persistent
pairing) as a possible separate product idea alongside LocalSync -
genuinely different problem from LocalSync's ongoing sync relationship
(one-off transfer vs. a paired, continuously-syncing pair of devices).
Not scoped, not started - noted here so it isn't lost, same as the
general-file-sync and per-PKM-unlock ideas elsewhere in this file's
history.

## Other revenue ideas beyond the core IAP ladder (alphabetical)

Not part of the Tier 0-5 ladder above - separate revenue concepts
raised same session, captured here for later evaluation, not decided
or scoped. Each notes whether it fits inside LocalSync's own brand or
needs to live as a separate product.

- **B2B / white-label licensing** - license the sync engine itself to
  other PKM apps directly, rather than only building per-PKM support
  yourself. Fits LocalSync - closer to the existing "enterprise
  licensing, taken seriously" idea than a new concept.
- **Blockchain-paid user credits** - pay users crypto/tokens for
  consented data sharing, real precedent in Brave Browser's BAT token
  (pays users for opted-in ad-attention data, while still positioning
  itself as privacy-respecting relative to Google/Facebook). **Separate
  app only** - see Data monetization below for why this can't live
  inside LocalSync itself.
- **Data monetization (consented device fingerprinting)** - user's own
  framing: "data mining and surveillance capitalism... if the users are
  informed and agree, that's a revenue stream," referencing app-
  fingerprinting research (mysk.co researchers publish this kind of
  finding, usually as a privacy warning, not a business template - the
  specific "Loupe" app referenced wasn't independently confirmed).
  **Separate app only, explicitly not LocalSync** - direct contradiction
  of LocalSync's own core promise ("your notes never touch a server you
  don't own or control"), real risk with the exact communities in
  LocalSync's own marketing plan (r/privacy, r/selfhosted, HN), and real
  App Store policy risk (App Tracking Transparency, privacy manifests
  specifically target this behavior). User confirmed 2026-08-26: yes,
  keep as a separate app, not merged into LocalSync's brand.
- **Donations / sponsorship** - Patreon/GitHub Sponsors-style support
  for the free tier specifically. Fits LocalSync well - matches the
  stated FOSS/Linux-community-respect values directly, and is how
  comparable respected tools in this space (Syncthing, Self-hosted
  LiveSync) already sustain themselves.
- **Paid priority support** - common indie-dev pattern, modest revenue,
  low build effort. Fits LocalSync, not yet prioritized.
- **Relay/discovery subscription** - already in the pricing ladder
  above `Projects/LocalSync.md`'s history: optional paid add-on for
  cross-network syncing, opt-in, core sync stays free and one-time
  regardless. The existing example of "accounts done right" for this
  brand - the shape any future accounts-based idea should match.
