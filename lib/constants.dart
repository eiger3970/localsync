// Single source for the target note-taking app's name, shown throughout
// the vault-setup UI. Obsidian is the only app synclocal actually talks to
// right now (via its obsidian:// URL scheme and On My iPhone/Obsidian
// folder) - this constant only swaps display text, not the real
// integration. Swapping to Joplin/Logseq/etc later still needs new
// URL-scheme and folder-path logic, this just avoids re-editing every
// on-screen string when that happens.
const String kNoteAppName = 'Obsidian';

// 2026-08-11: "what is a vault?" - real device review, from someone who
// knows Joplin/Notion/Tana but not Obsidian's own term for its data
// folder. "Vault" is Obsidian-specific jargon (Logseq: "graph", Joplin:
// "notebook") - same swap-point pattern as kNoteAppName, for our own
// descriptive copy only. Does NOT cover instructional text that quotes
// Obsidian's actual on-screen button labels ("Create a vault" inside the
// real Obsidian app) - that has to stay literally accurate to what's
// really on screen regardless of what synclocal calls the concept, and
// would need a full rewrite (not a word swap) for any other app anyway.
const String kContainerName = 'vault';
