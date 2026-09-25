/// Model suggestions from a local database a project already has: drift
/// tables, isar collections, and sqflite `CREATE TABLE` statements.
///
/// Adoption says these are printed and never applied. Nothing here writes, and
/// nothing guesses a sensitive field: whether a column holds something that
/// must not reach logs or clients is a judgement about meaning, and a guess
/// that under-redacts does so silently.
///
/// Read from source, like the rest of the CLI, with comments blanked.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'adoption_build_checks.dart';

/// One suggested field.
class DVLocalField {
  const DVLocalField(this.name, this.type, {required this.nullable});

  final String name;

  /// A Dartvel model field type: int, String, bool, double or DateTime.
  final String type;
  final bool nullable;
}

/// One table or collection, and the model it suggests.
class DVLocalTable {
  const DVLocalTable({
    required this.kind,
    required this.table,
    required this.model,
    required this.source,
    required this.fields,
    required this.unmapped,
  });

  /// `drift`, `isar` or `sqflite`.
  final String kind;

  /// The table or collection as declared.
  final String table;

  /// The public model name the suggestion uses.
  final String model;

  /// `lib/file.dart:line`.
  final String source;

  final List<DVLocalField> fields;

  /// Columns with no model field type, each naming the column and its type.
  final List<String> unmapped;
}

/// Every drift table, isar collection and sqflite table under `lib/`.
List<DVLocalTable> dvLocalSchemas(String root) {
  final Directory lib = Directory(p.join(root, 'lib'));
  if (!lib.existsSync()) return const <DVLocalTable>[];
  final List<File> files = lib
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .where((File f) => !f.path.endsWith('.g.dart'))
      .toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));
  final List<DVLocalTable> tables = <DVLocalTable>[];
  for (final File file in files) {
    final String rel = p.relative(file.path, from: root).replaceAll(r'\', '/');
    if (rel.startsWith('lib/dartvel_client/')) continue;
    final String code = dvBlankComments(file.readAsStringSync());
    final String masked = dvBlankStrings(code);
    tables
      ..addAll(_classes(rel, code, masked))
      ..addAll(_sqflite(rel, code, masked));
  }
  return tables;
}

/// The `@DVModel` input [table] suggests.
String dvModelSuggestion(DVLocalTable table) {
  // Written with a primary constructor, as a model is written by hand.
  final StringBuffer out = StringBuffer()
    ..writeln('@DVModel()')
    ..writeln('class const _${table.model}({');
  for (final DVLocalField field in table.fields) {
    out.writeln(
      '  ${field.nullable ? '' : 'required '}final '
      '${field.type}${field.nullable ? '?' : ''} ${field.name},',
    );
  }
  out.writeln('});');
  return out.toString();
}

/// The report `dartvel db pull --local` prints.
List<String> dvLocalSchemaReport(String root) {
  final List<DVLocalTable> tables = dvLocalSchemas(root);
  if (tables.isEmpty) {
    return const <String>[
      'No local database schema found: no drift tables (classes extending '
          'Table), isar collections (@collection classes) or sqflite '
          'CREATE TABLE statements under lib/. Nothing was written.',
    ];
  }
  final List<String> out = <String>[
    'Model suggestions from ${tables.length} local table(s). Nothing was '
        'written: copy what you want into a model file.',
    'Sensitivity is not inferred. Mark a field @DVModel.sensitiveField() '
        'yourself where it holds something that must not reach logs, AI '
        'context or clients.',
  ];
  for (final DVLocalTable table in tables) {
    out
      ..add('')
      ..add('${table.source}  ${table.kind} ${table.table}')
      ..addAll(dvModelSuggestion(table).trimRight().split('\n'));
    for (final String column in table.unmapped) {
      out.add('  not mapped: $column');
    }
  }
  return out;
}

const Map<String, String> _driftColumns = <String, String>{
  'IntColumn': 'int',
  'TextColumn': 'String',
  'BoolColumn': 'bool',
  'DateTimeColumn': 'DateTime',
  'RealColumn': 'double',
};

const Set<String> _modelTypes = <String>{
  'int',
  'String',
  'bool',
  'double',
  'DateTime',
};

Iterable<DVLocalTable> _classes(String rel, String code, String masked) sync* {
  for (final RegExpMatch match in dvClassDeclaration.allMatches(masked)) {
    final int open = masked.indexOf('{', match.end);
    if (open == -1) continue;
    final String header = masked.substring(match.end, open);
    final int close = _matchingBrace(masked, open);
    final String body = masked.substring(open + 1, close);
    final List<(String, int)> annotations =
        dvAnnotationsBefore(masked, match.start);
    final String name = match.group(1)!;
    final String source = '$rel:${_lineOf(masked, match.start)}';

    if (RegExp(r'\bextends\s+(?:[A-Za-z_]\w*\.)?Table\b').hasMatch(header)) {
      String model = name.length > 1 && name.endsWith('s') && !name.endsWith('ss')
          ? name.substring(0, name.length - 1)
          : name;
      for (final (String annotation, int at) in annotations) {
        if (annotation != 'DataClassName') continue;
        final Match? named = RegExp(
          r'''@(?:\w+\.)?DataClassName\s*\(\s*['"]([A-Za-z_]\w*)['"]''',
        ).matchAsPrefix(code, at);
        if (named != null) model = named.group(1)!;
      }
      yield _driftTable(name, model, source, body);
    } else if (annotations.any(((String, int) a) =>
        a.$1 == 'collection' || a.$1 == 'Collection')) {
      yield _isarCollection(name, source, body);
    }
  }
}

DVLocalTable _driftTable(String name, String model, String source, String body) {
  final List<DVLocalField> fields = <DVLocalField>[];
  final List<String> unmapped = <String>[];
  final RegExp getter = RegExp(
    r'([A-Za-z_]\w*(?:<\s*[A-Za-z_]\w*\s*>)?)\s+get\s+([A-Za-z_]\w*)\s*=>\s*([^;]*);',
  );
  for (final RegExpMatch m in getter.allMatches(body)) {
    final String declared = m.group(1)!.replaceAll(' ', '');
    final String column = m.group(2)!;
    final bool nullable = m.group(3)!.contains('.nullable()');
    final RegExpMatch? generic = RegExp(r'^Column<(\w+)>$').firstMatch(declared);
    final String? type = _driftColumns[declared] ??
        (generic != null && _modelTypes.contains(generic.group(1))
            ? generic.group(1)
            : null);
    if (type == null) {
      unmapped.add('$column ($declared): no Dartvel model field type; add it '
          'by hand');
      continue;
    }
    fields.add(DVLocalField(column, type, nullable: nullable));
  }
  return DVLocalTable(
    kind: 'drift',
    table: name,
    model: model,
    source: source,
    fields: fields,
    unmapped: unmapped,
  );
}

DVLocalTable _isarCollection(String name, String source, String body) {
  final List<DVLocalField> fields = <DVLocalField>[];
  final List<String> unmapped = <String>[];
  for (final String raw in _members(body)) {
    String member = raw.trim();
    bool ignored = false;
    final RegExp annotation = RegExp(r'^@([A-Za-z_][\w.]*)\s*(?:\([^)]*\))?\s*');
    for (RegExpMatch? a = annotation.firstMatch(member);
        a != null;
        a = annotation.firstMatch(member)) {
      if (a.group(1) == 'ignore' || a.group(1) == 'Ignore') ignored = true;
      member = member.substring(a.end);
    }
    if (ignored || member.startsWith('static ') || member.contains('=>')) {
      continue;
    }
    final RegExpMatch? field = RegExp(
      r'^(late\s+)?(?:final\s+)?([A-Za-z_][\w<>, ]*?)(\?)?\s+([A-Za-z_]\w*)\s*(?:=[\s\S]*)?$',
    ).firstMatch(member);
    if (field == null) continue;
    final String declared = field.group(2)!.trim();
    final String column = field.group(4)!;
    final String? type = declared == 'Id'
        ? 'int'
        : (_modelTypes.contains(declared) ? declared : null);
    if (type == null) {
      unmapped.add('$column ($declared${field.group(3) ?? ''}): no Dartvel '
          'model field type; add it by hand');
      continue;
    }
    fields.add(DVLocalField(column, type, nullable: field.group(3) != null));
  }
  return DVLocalTable(
    kind: 'isar',
    table: name,
    model: name,
    source: source,
    fields: fields,
    unmapped: unmapped,
  );
}

/// The declarations at the top of a class body: split at `;`, with a closing
/// brace that ends a member discarding what came before it, so methods fall
/// away rather than merging into the next field.
List<String> _members(String body) {
  final List<String> members = <String>[];
  int depth = 0;
  int start = 0;
  for (int i = 0; i < body.length; i += 1) {
    final String c = body[i];
    if (c == '(' || c == '[' || c == '{') depth += 1;
    if (c == ')' || c == ']' || c == '}') {
      depth -= 1;
      if (c == '}' && depth == 0) start = i + 1;
    }
    if (c == ';' && depth == 0) {
      members.add(body.substring(start, i));
      start = i + 1;
    }
  }
  return members;
}

final RegExp _createTable = RegExp(
  r'CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?[`"\[]?([A-Za-z_]\w*)[`"\]]?\s*\(',
  caseSensitive: false,
);

Iterable<DVLocalTable> _sqflite(String rel, String code, String masked) sync* {
  for (final RegExpMatch m in _createTable.allMatches(code)) {
    // Only inside a string literal, where the masked copy is blank.
    if (masked.substring(m.start, m.start + 6).trim().isNotEmpty) continue;
    final int open = m.end - 1;
    int depth = 0;
    int close = -1;
    for (int i = open; i < code.length; i += 1) {
      if (code[i] == '(') depth += 1;
      if (code[i] == ')') {
        depth -= 1;
        if (depth == 0) {
          close = i;
          break;
        }
      }
    }
    if (close == -1) continue;
    final String table = m.group(1)!;
    final List<DVLocalField> fields = <DVLocalField>[];
    final List<String> unmapped = <String>[];
    for (final String raw in _topLevelCommas(code.substring(open + 1, close))) {
      // Adjacent literals ('a' 'b') and the quotes around them are not SQL.
      final String definition = raw
          .replaceAll(RegExp(r'''['"]\s*\+?\s*['"]'''), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (definition.isEmpty) continue;
      final String upper = definition.toUpperCase();
      if (RegExp(r'^(PRIMARY|FOREIGN|UNIQUE|CHECK|CONSTRAINT)\b').hasMatch(upper)) {
        continue;
      }
      final List<String> words = definition.split(' ');
      final String column = words.first.replaceAll(RegExp(r'[`"\[\]]'), '');
      final String declared = words.length > 1 ? words[1].toUpperCase() : '';
      final String? type = declared.contains('BOOL')
          ? 'bool'
          : declared.contains('INT')
              ? 'int'
              : RegExp('CHAR|CLOB|TEXT').hasMatch(declared)
                  ? 'String'
                  : RegExp('REAL|FLOA|DOUB').hasMatch(declared)
                      ? 'double'
                      : null;
      if (type == null) {
        unmapped.add('$column (${declared.isEmpty ? 'no type' : declared}): '
            'no Dartvel model field type; add it by hand');
        continue;
      }
      final bool nullable =
          !upper.contains('NOT NULL') && !upper.contains('PRIMARY KEY');
      fields.add(DVLocalField(_camel(column), type, nullable: nullable));
    }
    yield DVLocalTable(
      kind: 'sqflite',
      table: table,
      model: _pascalSingular(table),
      source: '$rel:${_lineOf(code, m.start)}',
      fields: fields,
      unmapped: unmapped,
    );
  }
}

List<String> _topLevelCommas(String s) {
  final List<String> parts = <String>[];
  int depth = 0;
  int start = 0;
  for (int i = 0; i < s.length; i += 1) {
    if (s[i] == '(') depth += 1;
    if (s[i] == ')') depth -= 1;
    if (s[i] == ',' && depth == 0) {
      parts.add(s.substring(start, i));
      start = i + 1;
    }
  }
  parts.add(s.substring(start));
  return parts;
}

String _camel(String snake) {
  final List<String> parts =
      snake.split('_').where((String s) => s.isNotEmpty).toList();
  if (parts.isEmpty) return snake;
  return parts.first +
      parts.skip(1).map((String s) => s[0].toUpperCase() + s.substring(1)).join();
}

String _pascalSingular(String table) {
  final String pascal = table
      .split('_')
      .where((String s) => s.isNotEmpty)
      .map((String s) => s[0].toUpperCase() + s.substring(1))
      .join();
  return pascal.length > 1 && pascal.endsWith('s') && !pascal.endsWith('ss')
      ? pascal.substring(0, pascal.length - 1)
      : pascal;
}

int _matchingBrace(String s, int open) {
  int depth = 0;
  for (int i = open; i < s.length; i += 1) {
    if (s[i] == '{') depth += 1;
    if (s[i] == '}') {
      depth -= 1;
      if (depth == 0) return i;
    }
  }
  return s.length;
}

int _lineOf(String source, int offset) =>
    '\n'.allMatches(source.substring(0, offset)).length + 1;
