// Single source for the target note-taking app's name, shown throughout
// the vault-setup UI. Obsidian is the only app synclocal actually talks to
// right now (via its obsidian:// URL scheme and On My iPhone/Obsidian
// folder) - this constant only swaps display text, not the real
// integration. Swapping to Joplin/Logseq/etc later still needs new
// URL-scheme and folder-path logic, this just avoids re-editing every
// on-screen string when that happens.
const String kNoteAppName = 'Obsidian';
