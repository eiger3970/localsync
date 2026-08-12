// Single source for the target note-taking app's name, shown throughout
// the vault-setup UI. Obsidian is the only app localsync actually talks to
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
// really on screen regardless of what localsync calls the concept, and
// would need a full rewrite (not a word swap) for any other app anyway.
const String kContainerName = 'vault';

// 2026-08-11: "I think we can change all instances of Obsidian to PKM
// or Personal knowledge management" - split from kNoteAppName rather
// than repurposing it, since some of kNoteAppName's uses are literal
// instructions to tap a button in the real installed Obsidian app
// ("OPEN OBSIDIAN", "Install Obsidian from the App Store") - those have
// to keep saying the real app name or the instruction breaks. This one
// is for our own purely descriptive copy only (headings, glyph labels,
// the localsync-generated repo display name) - decided scope: chose
// "descriptive text only" over genericizing the action buttons too.
const String kGenericAppLabel = 'PKM';

// 2026-08-20: shown on the About screen (kebab menu). Manually kept in
// sync with pubspec.yaml's version: line - no package_info_plus
// dependency added just to read this at runtime (same reasoning this
// app has used before against adding native packages for something
// this small).
const String kAppVersion = '0.1.0';
