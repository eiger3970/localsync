// models/repository.dart

enum SyncStatus { idle, syncing, ok, error }

enum SyncPhase {
  idle,
  detecting,
  committing,
  fetching,
  pulling,
  pushing,
  merging,
  done,
}

extension SyncPhaseLabel on SyncPhase {
  String get label => switch (this) {
    SyncPhase.idle       => '',
    SyncPhase.detecting  => 'checking for changes',
    SyncPhase.committing => 'saving changes',
    SyncPhase.fetching   => 'reading desktop',
    SyncPhase.pulling    => 'downloading notes',
    SyncPhase.pushing    => 'uploading notes',
    SyncPhase.merging    => 'merging edits',
    SyncPhase.done       => 'up to date',
  };
}

class Repository {
  final int?       id;
  final String     name;
  final String     remoteHost;        // desktop's current hotspot-subnet IP
  final int        remotePort;        // 22
  final String     remoteUser;        // rapi5
  final String     remotePath;        // /home/rapi5/Documents/Git/pi5-obsidian/Git_bare_repo/localsync.git (isolated test repo, see main.dart)
  // Last known resolved on-disk path - informational/display only.
  // Cannot be trusted directly for git operations: this is now the
  // user's OWN Obsidian vault folder (a different app's sandbox),
  // access to which requires resolving vaultBookmark fresh via
  // VaultFolderService before every use, not just reading this string.
  final String     localPath;
  // Security-scoped bookmark (base64) granting access to the Obsidian
  // vault folder the user picked via the native folder picker. Added
  // 2026-08-09 - real user documentation of years of working Working
  // Copy usage revealed the correct architecture: Obsidian creates and
  // owns its vault folder itself; Localsync requests access to it
  // afterward, the same way Working Copy's "Link Repository to" does.
  // localPath alone was never going to work for this - iOS requires a
  // bookmark to retain cross-app folder access across launches, a
  // plain path string silently loses access. Empty for repos created
  // before this existed (see localPath's own prior empty-string
  // migration note in STRUCTURE.md for the analogous earlier case).
  final String     vaultBookmark;
  final String     obsidianVaultPath; // On My iPhone/Obsidian/<vault name> (display only)
  final bool       autoSync;
  final SyncStatus status;
  final SyncPhase  syncPhase;
  final DateTime?  lastSync;
  // 2026-08-20: "show error in human language, how to fix it, then the
  // error code verbose details - you've done this format with some
  // errors but not others" - lastError used to be the diagnosis,
  // resolution, and raw exception text all pre-joined into one string
  // (with '\n\nRaw error...\n' as a literal separator), which is why
  // home_screen.dart's sync-error dialog could only ever show one
  // undifferentiated block instead of the labeled WHAT
  // HAPPENED/HOW TO FIX IT/RAW ERROR cards the setup flow already used
  // (linking_state.dart's LinkingError, shown via widgets/diag_card.dart).
  // Split into three fields so both places can render the same way.
  // lastError itself keeps its name but is now just the diagnosis.
  final String?    lastError;
  final String?    lastErrorResolution;
  final String?    lastErrorDebug;
  final int        fileCount;
  final int        folderCount;

  const Repository({
    this.id,
    required this.name,
    required this.remoteHost,
    required this.remoteUser,
    required this.remotePath,
    required this.localPath,
    this.vaultBookmark = '',
    required this.obsidianVaultPath,
    this.remotePort   = 22,
    this.autoSync     = true,
    this.status       = SyncStatus.idle,
    this.syncPhase    = SyncPhase.idle,
    this.lastSync,
    this.lastError,
    this.lastErrorResolution,
    this.lastErrorDebug,
    this.fileCount    = 0,
    this.folderCount  = 0,
  });

  Repository copyWith({
    int?         id,
    String?      name,
    String?      remoteHost,
    int?         remotePort,
    String?      remoteUser,
    String?      remotePath,
    String?      localPath,
    String?      vaultBookmark,
    String?      obsidianVaultPath,
    bool?        autoSync,
    SyncStatus?  status,
    SyncPhase?   syncPhase,
    DateTime?    lastSync,
    String?      lastError,
    String?      lastErrorResolution,
    String?      lastErrorDebug,
    int?         fileCount,
    int?         folderCount,
  }) => Repository(
    id:                id               ?? this.id,
    name:              name             ?? this.name,
    remoteHost:        remoteHost       ?? this.remoteHost,
    remotePort:        remotePort       ?? this.remotePort,
    remoteUser:        remoteUser       ?? this.remoteUser,
    remotePath:        remotePath       ?? this.remotePath,
    localPath:         localPath        ?? this.localPath,
    vaultBookmark:     vaultBookmark    ?? this.vaultBookmark,
    obsidianVaultPath: obsidianVaultPath ?? this.obsidianVaultPath,
    autoSync:          autoSync         ?? this.autoSync,
    status:            status           ?? this.status,
    syncPhase:         syncPhase        ?? this.syncPhase,
    lastSync:          lastSync         ?? this.lastSync,
    lastError:         lastError        ?? this.lastError,
    lastErrorResolution: lastErrorResolution ?? this.lastErrorResolution,
    lastErrorDebug:    lastErrorDebug   ?? this.lastErrorDebug,
    fileCount:         fileCount        ?? this.fileCount,
    folderCount:       folderCount      ?? this.folderCount,
  );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'name':           name,
    'remote_host':    remoteHost,
    'remote_port':    remotePort,
    'remote_user':    remoteUser,
    'remote_path':    remotePath,
    'local_path':     localPath,
    'vault_bookmark': vaultBookmark,
    'obsidian_vault': obsidianVaultPath,
    'auto_sync':      autoSync ? 1 : 0,
    'last_sync':      lastSync?.toIso8601String(),
    'last_error':     lastError,
    'last_error_resolution': lastErrorResolution,
    'last_error_debug': lastErrorDebug,
    'file_count':     fileCount,
    'folder_count':   folderCount,
  };

  factory Repository.fromMap(Map<String, dynamic> m) => Repository(
    id:                m['id'] as int?,
    name:              m['name'] as String,
    remoteHost:        m['remote_host'] as String,
    remotePort:        (m['remote_port'] as int?) ?? 22,
    remoteUser:        m['remote_user'] as String,
    remotePath:        m['remote_path'] as String,
    // Old records saved before 2026-08-09 have no local_path at all -
    // falls back to empty string rather than crashing on parse. A repo
    // loaded this way will still fail to sync (same as before this fix)
    // until it's removed and re-added via SET UP VAULT.
    localPath:         (m['local_path'] as String?) ?? '',
    vaultBookmark:     (m['vault_bookmark'] as String?) ?? '',
    obsidianVaultPath: m['obsidian_vault'] as String,
    autoSync:          (m['auto_sync'] as int? ?? 1) == 1,
    status:            SyncStatus.idle,
    lastSync:          m['last_sync'] != null
                         ? DateTime.tryParse(m['last_sync'] as String)
                         : null,
    lastError:         m['last_error'] as String?,
    lastErrorResolution: m['last_error_resolution'] as String?,
    lastErrorDebug:    m['last_error_debug'] as String?,
    fileCount:         (m['file_count'] as int?) ?? 0,
    folderCount:       (m['folder_count'] as int?) ?? 0,
  );
}
