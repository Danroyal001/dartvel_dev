/// The database adapter contract plus the in-memory development adapter.
library dartvel_core.database.adapter;

abstract class DVDatabaseAdapter {
  Future<List<Map<String, Object?>>> query(String sql, [List<Object?>? params]);
  Future<int> execute(String sql, [List<Object?>? params]);
}

class MemoryDVDatabaseAdapter implements DVDatabaseAdapter {
  final Map<String, List<Map<String, Object?>>> _tables = {};

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?>? params,
  ]) async {
    final normalized = sql.trim().replaceAll(RegExp(r'\s+'), ' ');
    final lower = normalized.toLowerCase();
    if (lower == 'select 1') {
      return const [
        {'1': 1}
      ];
    }

    final match =
        RegExp(r'^select \* from ([a-zA-Z_][\w]*)$', caseSensitive: false)
            .firstMatch(normalized);
    if (match != null) {
      return List<Map<String, Object?>>.from(
        _tables[match.group(1)!] ?? const <Map<String, Object?>>[],
      );
    }
    throw ArgumentError(
        'MemoryDVDatabaseAdapter supports select 1 and select * from <table>.');
  }

  @override
  Future<int> execute(String sql, [List<Object?>? params]) async {
    final normalized = sql.trim().replaceAll(RegExp(r'\s+'), ' ');
    final insert = RegExp(
      r'^insert into ([a-zA-Z_][\w]*) \(([^)]+)\) values \(([^)]+)\)$',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (insert != null) {
      final table = insert.group(1)!;
      final columns = insert.group(2)!.split(',').map((c) => c.trim()).toList();
      final values =
          params ?? insert.group(3)!.split(',').map(_literal).toList();
      if (columns.length != values.length) {
        throw ArgumentError('Column count does not match value count.');
      }
      final row = <String, Object?>{};
      for (var i = 0; i < columns.length; i++) {
        row[columns[i]] = values[i];
      }
      (_tables[table] ??= []).add(row);
      return 1;
    }

    final delete =
        RegExp(r'^delete from ([a-zA-Z_][\w]*)$', caseSensitive: false)
            .firstMatch(normalized);
    if (delete != null) {
      final table = delete.group(1)!;
      final count = _tables[table]?.length ?? 0;
      _tables[table] = [];
      return count;
    }
    throw ArgumentError(
        'MemoryDVDatabaseAdapter supports insert and delete statements.');
  }

  static Object? _literal(String value) {
    final trimmed = value.trim();
    if (trimmed == '?') return null;
    if (trimmed.startsWith("'") && trimmed.endsWith("'")) {
      return trimmed.substring(1, trimmed.length - 1);
    }
    return num.tryParse(trimmed) ?? trimmed;
  }
}
