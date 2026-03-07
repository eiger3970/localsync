// models/commit_template.dart
// Commit message templates sorted by usage frequency (ML-lite).

class CommitTemplate {
  final int?   id;
  final String label;    // e.g. "quick sync"
  final String pattern;  // e.g. "quick sync" or "update [file]"
  final int    useCount;
  final DateTime? lastUsed;

  const CommitTemplate({
    this.id,
    required this.label,
    required this.pattern,
    this.useCount = 0,
    this.lastUsed,
  });

  CommitTemplate copyWith({int? useCount, DateTime? lastUsed}) => CommitTemplate(
    id:       id,
    label:    label,
    pattern:  pattern,
    useCount: useCount  ?? this.useCount,
    lastUsed: lastUsed  ?? this.lastUsed,
  );

  Map<String, dynamic> toMap() => {
    'id':        id,
    'label':     label,
    'pattern':   pattern,
    'use_count': useCount,
    'last_used': lastUsed?.toIso8601String(),
  };

  factory CommitTemplate.fromMap(Map<String, dynamic> m) => CommitTemplate(
    id:       m['id'] as int?,
    label:    m['label'] as String,
    pattern:  m['pattern'] as String,
    useCount: (m['use_count'] as int?) ?? 0,
    lastUsed: m['last_used'] != null
                ? DateTime.parse(m['last_used'] as String)
                : null,
  );
}

// Default templates shipped with the app.
const kDefaultTemplates = [
  CommitTemplate(label: 'quick sync',        pattern: 'quick sync'),
  CommitTemplate(label: 'update [file]',     pattern: 'update [file]'),
  CommitTemplate(label: 'add [feature]',     pattern: 'add [feature]'),
  CommitTemplate(label: 'fix [issue]',       pattern: 'fix [issue]'),
  CommitTemplate(label: 'merge [branch]',    pattern: 'merge [branch]'),
  CommitTemplate(label: 'refactor [code]',   pattern: 'refactor [code]'),
  CommitTemplate(label: 'remove [file]',     pattern: 'remove [file]'),
];
