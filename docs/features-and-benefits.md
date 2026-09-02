# LocalSync - Features & Benefits

Local-first sync for plaintext PKMs (Obsidian, Logseq, Joplin, and anything
else that stores notes as markdown files on disk). No cloud. No subscription.

## Price

**$49.99 once. Lifetime. Every supported PKM, not just one.**

Less than one year of the cheapest official sync add-on - yours forever
after that, on every plaintext PKM you use, not locked to a single app.

## Features

- Syncs over your own network (home WiFi, hotspot) directly between your
  phone and desktop - nothing passes through a third-party server, ever.
- Real conflict resolution built for PKM files specifically - Kanban
  boards, stacked edits, and markdown structure are understood and merged,
  not just dumped as a duplicate `-conflict` file for you to sort out by
  hand.
- One-time purchase. No monthly fee, no subscription, no recurring charge
  of any kind.
- Works with any plaintext-based PKM - Obsidian, Logseq, Joplin, and
  others - not locked to a single app's ecosystem.
- Transmission is SSH the whole way, key-based authentication, encrypted
  in transit by protocol design - not a bolt-on feature, the only way it
  ever talks to your desktop.
- No account, no registration, no email required to use the app.
- Auto sync on launch, manual pull/push always available, full commit
  history preserved (it's real git underneath).

## Benefits

- **Privacy**: your notes never touch a server you don't own or control,
  encrypted or not - the only two places your plaintext ever exists are
  your own devices.
- **No recurring cost**: pay once, use it for as long as you use the app -
  no bill that keeps arriving whether you're actively using it or not.
- **No vendor lock-in**: if a sync provider shuts down or changes terms,
  cloud-synced users lose access; local-first sync doesn't depend on
  anyone else staying in business.
- **Works offline**: phone and desktop syncing over the same network
  doesn't need an internet connection at all.
- **Real merge, not manual cleanup**: conflicts get resolved with an
  understanding of what a PKM file actually is, not treated as generic
  binary blobs.

## Honest limitations (say this, don't hide it)

- **Not a backup solution.** Local-first sync protects against "my two
  devices disagree," not against "my house burned down." Cloud storage
  exists for people who need that stronger, off-site backup - if that's
  you, use both: LocalSync for private day-to-day sync, a separate cloud
  or off-site copy for disaster recovery.
- **Same-network setup today.** Phone and desktop sync easily when
  they're on the same WiFi/hotspot; syncing across separate locations
  (phone away from home) needs the desktop reachable some other way -
  say this upfront rather than let someone discover it after buying.
- **Some setup required.** SSH keys and a bare repo path aren't
  one-tap-and-done the way a cloud account is. Auto-discovery removes
  some of this friction but doesn't remove all of it yet.

## How it compares

Positioned without naming competitors by name in customer-facing copy -
internally, "Competitor A" tracks general-purpose peer-to-peer sync tools,
"Competitor B" tracks generic git-client-based sync, "Official sync" tracks
each PKM vendor's own paid add-on.

| | LocalSync | Competitor A | Competitor B | Official PKM sync |
|---|---|---|---|---|
| Price | $49.99 once | Free | One-time/subscription | $4-8/month, forever |
| Local network, no cloud relay | Yes | Yes | No | No |
| Understands PKM conflicts | Yes | No (duplicate files) | No (generic git merge) | Yes |
| Works across every PKM you use | Yes | Yes (but no PKM awareness) | Yes (but no PKM awareness) | No (locked to one app) |
| Setup | IP + SSH key | Peer ID pairing | Git remote config | Account only |

## Why this is priced as one-time, not subscription

The pitch is direct: pay once, less than a single year of what the
official add-on charges every year forever. That only works as an honest
claim if the price stays comfortably under a year of the cheapest real
competitor - which is why $49.99 (not higher) is the ceiling for this
model to keep making sense.
