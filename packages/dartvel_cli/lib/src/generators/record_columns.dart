import 'package:dartvel_core/dartvel.dart' show DVHistory, DVRecordTable;

/// A column every generated model table carries beside its fields, for
/// [DVRecordTable], which generated persistence writes through.
class DVRecordColumn {
  const DVRecordColumn(
    this.name, {
    required this.type,
    required this.nullable,
    this.defaultSql,
  });

  final String name;
  final String type;
  final bool nullable;

  /// The default as SQL, or null for none.
  final String? defaultSql;

  /// The column as it is written in `CREATE TABLE` and `ADD COLUMN`.
  String get definition =>
      '$name $type${nullable ? '' : ' NOT NULL'}'
      '${defaultSql == null ? '' : ' DEFAULT $defaultSql'}';

  /// How `.dart_tool/dartvel_schema.g.json` records the column's type, so
  /// `dartvel db migrate` adds it as this rather than as nullable TEXT.
  Map<String, Object?> toJson() => <String, Object?>{
        'type': type,
        'nullable': nullable,
        if (defaultSql != null) 'default': defaultSql,
      };
}

/// The bookkeeping columns, in the order [DVRecordTable] stores them.
///
/// The version is `NOT NULL DEFAULT 1` because of the rows that are already
/// there. The privacy walk, change capture and every generated save write a
/// row only where `_dv_version = ?` still matches what they read, and NULL
/// matches nothing: a table migrated with NULL versions has rows that every
/// conditional write refuses and every sweep skips for ever, reporting each
/// run as contended. A constant default gives each existing row version one,
/// which is also what [DVRecordTable] would have given it on insert, and adds
/// the column without rewriting the table on every server that keeps the
/// default in its catalogue.
const List<DVRecordColumn> dvRecordColumns = <DVRecordColumn>[
  DVRecordColumn(
    DVRecordTable.versionColumn,
    type: 'INTEGER',
    nullable: false,
    defaultSql: '1',
  ),
  DVRecordColumn(DVRecordTable.deletedColumn, type: 'TEXT', nullable: true),
];

/// `history:` on a `@DVModel`, as the policy and the Dart that constructs
/// it, or null when the model declares none.
///
/// Anything it cannot read is refused through [refuse] rather than ignored:
/// a history the generator skipped is a model whose change log is silently
/// never written.
({DVHistory history, String source})? dvHistoryArg(
  String? raw,
  Never Function(String message) refuse,
) {
  if (raw == null) return null;
  final String text = raw.trim().replaceFirst(RegExp(r'^const\s+'), '');
  const String usage =
      'Write DVHistory() or DVHistory(keep: Duration(days: 365))';
  final RegExpMatch? call =
      RegExp(r'^DVHistory\s*\(([\s\S]*)\)$').firstMatch(text);
  if (call == null) refuse('history: $text is not a history policy. $usage');
  final String inner = call.group(1)!.trim();
  if (inner.isEmpty) return (history: const DVHistory(), source: 'DVHistory()');
  final RegExpMatch? keep = RegExp(
    r'^keep\s*:\s*(?:const\s+)?Duration\s*\(([^()]*)\)\s*,?$',
  ).firstMatch(inner);
  if (keep == null) refuse('history: $text is not a history policy. $usage');
  const List<String> units = <String>['days', 'hours', 'minutes', 'seconds'];
  final Map<String, int> parts = <String, int>{};
  for (final String part in keep.group(1)!.split(',')) {
    if (part.trim().isEmpty) continue;
    final RegExpMatch? unit =
        RegExp(r'^\s*(days|hours|minutes|seconds)\s*:\s*(\d+)\s*$')
            .firstMatch(part);
    if (unit == null) {
      refuse('history: keep takes a Duration of whole days, hours, minutes '
          'or seconds; "${part.trim()}" is not one. $usage');
    }
    parts[unit.group(1)!] = int.parse(unit.group(2)!);
  }
  final Duration kept = Duration(
    days: parts['days'] ?? 0,
    hours: parts['hours'] ?? 0,
    minutes: parts['minutes'] ?? 0,
    seconds: parts['seconds'] ?? 0,
  );
  if (kept <= Duration.zero) {
    refuse('history: keep is $kept, which would remove every entry as it is '
        'written. Keep it for longer, or write DVHistory() to keep entries '
        'until they are removed deliberately');
  }
  return (
    history: DVHistory(keep: kept),
    source: 'DVHistory(keep: Duration('
        '${units.where(parts.containsKey).map((String u) => '$u: ${parts[u]}').join(', ')}))',
  );
}

/// The columns of a model's history table, in the order [DVRecordTable]
/// writes an entry.
///
/// Typed, where the record table's own `ensureSchema` leaves them untyped,
/// because the migration is also written out for PostgreSQL, which requires
/// a type. A model declaring `history:` writes its entry in the same step as
/// the change and rolls the change back when the entry cannot be written
/// (`DV-HISTORY-005`), so a migration that made the table and not its log
/// would leave the model unable to save anything at all.
const List<DVRecordColumn> dvHistoryColumns = <DVRecordColumn>[
  DVRecordColumn('entry_id', type: 'TEXT', nullable: true),
  DVRecordColumn('record_key', type: 'TEXT', nullable: true),
  DVRecordColumn('record_version', type: 'INTEGER', nullable: true),
  DVRecordColumn('actor', type: 'TEXT', nullable: true),
  DVRecordColumn('tenant', type: 'TEXT', nullable: true),
  DVRecordColumn('transaction_id', type: 'TEXT', nullable: true),
  DVRecordColumn('occurred_at', type: 'TEXT', nullable: true),
  DVRecordColumn('changes', type: 'TEXT', nullable: true),
  DVRecordColumn('deleted', type: 'INTEGER', nullable: true),
  DVRecordColumn('restored', type: 'INTEGER', nullable: true),
];

/// The statement that creates [table]'s history table.
String dvHistoryCreateSql(String table) =>
    'CREATE TABLE IF NOT EXISTS ${table}__history '
    '(${dvHistoryColumns.map((DVRecordColumn c) => c.definition).join(', ')})';
