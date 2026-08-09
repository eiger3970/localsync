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
  final String     remotePath;        // /home/rapi5/Documents/Git/pi5-obsidian/Git_bare_repo/Md_files_bare.git
  final String     obsidianVaultPath; // On My iPhone/Synclocal
  final bool       autoSync;
  final SyncStatus status;
  final SyncPhase  syncPhase;
  final DateTime?  lastSync;
  final String?    lastError;
  final int        fileCount;
  final int        folderCount;

  const Repository({
    this.id,
    required this.name,
    required this.remoteHost,
    required this.remoteUser,
    required this.remotePath,
    required this.obsidianVaultPath,
    this.remotePort   = 22,
    this.autoSync     = true,
    this.status       = SyncStatus.idle,
    this.syncPhase    = SyncPhase.idle,
    this.lastSync,
    this.lastError,
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
    String?      obsidianVaultPath,
    bool?        autoSync,
    SyncStatus?  status,
    SyncPhase?   syncPhase,
    DateTime?    lastSync,
    String?      lastError,
    int?         fileCount,
    int?         folderCount,
  }) => Repository(
    id:                id               ?? this.id,
    name:              name             ?? this.name,
    remoteHost:        remoteHost       ?? this.remoteHost,
    remotePort:        remotePort       ?? this.remotePort,
    remoteUser:        remoteUser       ?? this.remoteUser,
    remotePath:        remotePath       ?? this.remotePath,
    obsidianVaultPath: obsidianVaultPath ?? this.obsidianVaultPath,
    autoSync:          autoSync         ?? this.autoSync,
    status:            status           ?? this.status,
    syncPhase:         syncPhase        ?? this.syncPhase,
    lastSync:          lastSync         ?? this.lastSync,
    lastError:         lastError        ?? this.lastError,
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
    'obsidian_vault': obsidianVaultPath,
    'auto_sync':      autoSync ? 1 : 0,
    'last_sync':      lastSync?.toIso8601String(),
    'last_error':     lastError,
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
    obsidianVaultPath: m['obsidian_vault'] as String,
    autoSync:          (m['auto_sync'] as int? ?? 1) == 1,
    status:            SyncStatus.idle,
    lastSync:          m['last_sync'] != null
                         ? DateTime.tryParse(m['last_sync'] as String)
                         : null,
    lastError:         m['last_error'] as String?,
    fileCount:         (m['file_count'] as int?) ?? 0,
    folderCount:       (m['folder_count'] as int?) ?? 0,
  );
}
