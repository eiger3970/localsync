# Conflict-resolution pricing tiers

## SUPERSEDED 2026-08-26 - free/paid boundary moved to PKM-awareness itself

Everything below this notice was written earlier the same day and is now
the **wrong split**. Kept for the reasoning trail, not as current
direction - see `Projects/LocalSync.md`'s Business summary (Obsidian
vault, dated entries) for the authoritative, canonical business model.

**The new boundary, user's own words**: "no pkm, only user files on
desktop and phone, nothing to do with the intricate setup that was
solved with much research and I think you coded in some algorithm for
automation." Confirmed directly (not inferred) after asking specifically
whether Obsidian-aware handling itself stays free - it does not.

- **Free**: generic file sync, phone <-> desktop, the user's own two
  devices. No PKM awareness of any kind - no Obsidian vault detection,
  no markdown/Kanban-structure-aware conflict repair, none of the
  guided vault-linking automation (the whole 8-step pairing sequence,
  `VaultFolderService`, the "New tab"/force-close vault-creation recipe
  from `[[project_synclocal_vault_recipe]]`). Just files, synced.
- **IAP**: turns on PKM-aware behavior, starting with Obsidian - the
  entire vault-linking/pairing flow and PKM-structure-aware conflict
  handling that's been built across many sessions becomes the paid
  unlock, not the free baseline. Other PKMs (LogSeq, Notion, Joplin,
  Tana) layer on top of this same paid tier per the existing
  per-PKM-unlock idea in `Projects/LocalSync.md`, not as separate free
  add-ons.

**Real implication, not yet built**: the free tier as newly defined
does not exist in the app at all today - literally everything built so
far (onboarding, linking, sync, conflict resolution) assumes an
Obsidian vault. A genuinely new, simpler sync mode (pick a folder on
each device, sync it, no vault/PKM concept involved) is a real feature
to design and build, not a relabeling of what's already there. Needs
its own scoping pass before starting - this doc only records the
decision, not an implementation plan.

Below this line: the original (now superseded) write-up, for the
merge/conflict feature specifically, kept for its still-useful
reasoning about the picker/merge tiers themselves (which still apply
*within* the paid PKM-aware tier, just no longer define the free/paid
boundary on their own).

---

This is about the merge/conflict feature specifically - separate from the
base app price ($49.99 once, lifetime - see `features-and-benefits.md`).
Written 2026-08-26 to make the tier boundaries explicit before more UI or
entitlement code gets built around them.

## The three tiers (2026-08-26 proposal)

| Tier | Comparison view | Merge action |
|---|---|---|
| **Free** (base app) | Plain text, in Obsidian | Manual - you edit the note yourself |
| **IAP** | Visual, side-by-side (vimdiff-style) | Manual - tap to keep one side |
| **IAP premium** | Visual, side-by-side | Automatic - put/yank individual pieces from each side |

Vimdiff-style comparison itself may stay free-tier-excluded except for
simple cases (short, 2-way conflicts) - see "Known constraint" below for
why that boundary already exists in the code independent of payment.

## What's already built vs. what's new

**Already real, already decided** (2026-08-18 business-model decision,
`purchase_service.dart` + `conflict_picker_upsell.dart`):
- Free tier = today's actual behavior. Full manual, raw-text conflict
  resolution already works, nothing held back.
- One IAP ($19.99 placeholder price, RevenueCat entitlement id
  `conflict_picker`) = the visual side-by-side word-diff picker
  (`conflict_picker_screen.dart`), "tap to keep" - still a *manual* pick,
  just with a real comparison view instead of raw markdown. This maps
  directly to the "IAP: visual manual" tier above.
- The upsell widget (`ConflictPickerUpsell`) is fully built but
  **deliberately not wired into the live screens yet** - wiring it in
  would gate a feature that's currently free during real-device testing,
  and there's no funded Apple Developer account / RevenueCat project set
  up to actually sell it yet.

**Not built at all yet:**
- Any form of automatic merge. Nothing today combines two versions of
  prose into one - "kept" + a reference callout is a safety net (nothing
  silently lost), not a merge. A "premium, automatic put/yank" tier is a
  real feature to design and build, not a paywall to flip on existing
  code.
- A second, higher-priced entitlement tier and its gating logic.

## Known constraint worth deciding around

`conflict_picker_screen.dart`'s `useDiff` check
(`versions.length == 2 && each side <= maxDiffTokens * 6` chars, see
`word_diff.dart`) gates the vimdiff-style view by **size/complexity**,
not by purchase status - a large or 3+-way stacked conflict falls back to
plain text for everyone, free or paid, today. If the intent is "paid
users get vimdiff even for large/complex conflicts, free users only for
simple ones," that needs its own logic beyond just adding an entitlement
check - the current fallback exists because a diff against an
arbitrarily-chosen "other" side among 3+ versions would be misleading,
not because of a size limit alone.
