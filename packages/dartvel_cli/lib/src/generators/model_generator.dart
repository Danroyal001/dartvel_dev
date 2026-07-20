import 'dart:io';

import 'package:file/local.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

class ModelGenerator {
  static Future<void> generate({
    required String root,
    required String pkgName,
    required String buildId,
  }) async {
    final modelsDir = Directory(p.join(root, 'lib', 'models'));
    final fs = const LocalFileSystem();
    final glob = Glob(p.join('lib', 'models', '**.dart'));
    final files = <File>[];
    if (modelsDir.existsSync()) {
      for (final entity
          in glob.listFileSystemSync(fs, root: root, followLinks: false)) {
        if (entity is File) {
          files.add(File(entity.path));
        }
      }
    }

    final sb = StringBuffer();
    sb.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
    sb.writeln(
        '// ignore_for_file: directives_ordering, non_constant_identifier_names, unused_element, use_super_parameters');
    sb.writeln('// Build ID: $buildId');
    sb.writeln();
    sb.writeln("import 'dart:convert' as convert;");
    sb.writeln();
    sb.writeln("import 'package:dartvel_core/dartvel.dart';");

    final modelImports = <String>[];
    final classesGenerated = <String>[];

    for (final file in files) {
      final abs = file.path;
      final rel = p.relative(abs, from: root).replaceAll('\\', '/');
      final importPath =
          rel.replaceFirst(RegExp(r'^lib/'), 'package:$pkgName/');
      modelImports.add("import '$importPath';");

      final content = await file.readAsString();
      // Scan for @DVModel(...) classes.
      final classMatches = RegExp(
        r'@DVModel\s*\(([^)]*)\)\s*class\s+([A-Za-z0-9_]+)\b',
        dotAll: true,
      ).allMatches(content);
      for (final match in classMatches) {
        final modelArgs = match.group(1) ?? '';
        final className = match.group(2)!;
        final isSearchableModel = modelArgs.contains(
          RegExp(r'\bsearchable\s*:\s*true\b'),
        );
        classesGenerated.add(className);

        // Parse fields
        // We find all fields of format: final Type name;
        final fieldRegex =
            RegExp(r'final\s+([A-Za-z0-9_<>?]+)\s+([A-Za-z0-9_]+)\b');
        final fields = <Map<String, String>>[];
        for (final m in fieldRegex.allMatches(content)) {
          fields.add({
            'type': m.group(1)!,
            'name': m.group(2)!,
          });
        }
        final searchableFields = <Map<String, String>>[];
        final searchableFieldRegex = RegExp(
          r'@DVSearchable\s*\(\s*\)\s*final\s+([A-Za-z0-9_<>?]+)\s+([A-Za-z0-9_]+)\b',
        );
        for (final m in searchableFieldRegex.allMatches(content)) {
          searchableFields.add({
            'type': m.group(1)!,
            'name': m.group(2)!,
          });
        }

        // Generate extension
        sb.writeln();
        sb.writeln('/// Dartvel generated extension for [$className]');
        sb.writeln('extension ${className}DartvelExtension on $className {');

        // toJson
        sb.writeln('  /// Serializes [$className] to a JSON map.');
        sb.writeln('  Map<String, dynamic> toJson() => {');
        for (final field in fields) {
          final name = field['name']!;
          sb.writeln("    '$name': $name,");
        }
        sb.writeln('  };');

        // copyWith
        sb.writeln();
        sb.writeln(
            '  /// Returns a copy of [$className] with the given fields replaced.');
        final params =
            fields.map((f) => "${f['type']}? ${f['name']}").join(', ');
        sb.writeln('  $className copyWith({$params}) {');
        sb.writeln('    return $className(');
        for (final field in fields) {
          final name = field['name']!;
          sb.writeln('      $name: $name ?? this.$name,');
        }
        sb.writeln('    );');
        sb.writeln('  }');

        // Database metadata
        final tableName = '${className.toLowerCase()}s';
        sb.writeln();
        sb.writeln('  /// Database table name for [$className].');
        sb.writeln("  String get tableName => '$tableName';");
        sb.writeln();
        sb.writeln('  /// SQL statement to create the [$className] table.');
        final cols = fields.map((f) => "${f['name']} TEXT").join(', ');
        sb.writeln(
            "  String get createTableSql => 'CREATE TABLE IF NOT EXISTS $tableName ($cols)';");

        sb.writeln('}');

        // Helper fromJson
        sb.writeln();
        sb.writeln('/// Helper class for parsing [$className] from JSON.');
        sb.writeln('class ${className}Parser {');
        sb.writeln('  /// Parses [$className] from a JSON map.');
        sb.writeln('  static $className fromJson(Map<String, dynamic> json) {');
        sb.writeln('    return $className(');
        for (final field in fields) {
          final name = field['name']!;
          final type = field['type']!;
          sb.writeln("      $name: json['$name'] as $type,");
        }
        sb.writeln('    );');
        sb.writeln('  }');
        sb.writeln('}');

        // Generated form controls helper
        sb.writeln();
        sb.writeln('/// Generated form controls for [$className]');
        sb.writeln('class ${className}FormControls extends DVFormControls {');
        sb.writeln('  final $className? ${className.toLowerCase()};');
        sb.writeln('  ${className}FormControls({');
        sb.writeln('    this.${className.toLowerCase()},');
        sb.writeln('    super.onSubmit,');
        sb.writeln('    super.onReset,');
        sb.writeln('  }) : super(${className.toLowerCase()});');

        for (final field in fields) {
          final name = field['name']!;
          final type = field['type']!;
          var defaultVal = 'null';
          if (type == 'String') {
            defaultVal = "''";
          } else if (type == 'int') {
            defaultVal = '0';
          } else if (type == 'double') {
            defaultVal = '0.0';
          } else if (type == 'bool') {
            defaultVal = 'false';
          }

          sb.writeln();
          sb.writeln(
              '  $type get $name => ${className.toLowerCase()}?.$name ?? $defaultVal;');
          if (name.toLowerCase().contains('email')) {
            sb.writeln(
                "  bool get ${name}IsValid => $name.isNotEmpty && $name.contains('@');");
          } else {
            sb.writeln('  bool get ${name}IsValid => true;');
          }
        }
        sb.writeln('}');
        sb.writeln();
        sb.writeln('final bool _registered_$className = () {');
        sb.writeln(
            '  registerFormControlsFactory<$className>((model, {onSubmit, onReset}) {');
        sb.writeln('    return ${className}FormControls(');
        sb.writeln('      ${className.toLowerCase()}: model as $className?,');
        sb.writeln('      onSubmit: onSubmit,');
        sb.writeln('      onReset: onReset,');
        sb.writeln('    );');
        sb.writeln('  });');
        sb.writeln('  return true;');
        sb.writeln('}();');

        sb.writeln();
        sb.writeln('/// Generated bulk import helpers for [$className].');
        sb.writeln('class ${className}Import {');
        sb.writeln('  static DVImportResult<$className> csv(String content) {');
        sb.writeln('    final lines = const convert.LineSplitter()');
        sb.writeln('        .convert(content)');
        sb.writeln('        .where((line) => line.trim().isNotEmpty)');
        sb.writeln('        .toList(growable: false);');
        sb.writeln('    if (lines.isEmpty) {');
        sb.writeln(
            '      return const DVImportResult<$className>(items: <$className>[]);');
        sb.writeln('    }');
        sb.writeln('    final headers = _splitCsvLine(lines.first);');
        sb.writeln('    final items = <$className>[];');
        sb.writeln('    final errors = <DVImportRowError>[];');
        sb.writeln(
            '    for (var index = 1; index < lines.length; index += 1) {');
        sb.writeln('      final values = _splitCsvLine(lines[index]);');
        sb.writeln('      final row = <String, dynamic>{};');
        sb.writeln('      for (var i = 0; i < headers.length; i += 1) {');
        sb.writeln(
            "        row[headers[i]] = i < values.length ? values[i] : '';");
        sb.writeln('      }');
        sb.writeln('      try {');
        sb.writeln('        items.add(${className}Parser.fromJson(row));');
        sb.writeln('      } on Object catch (error) {');
        sb.writeln('        errors.add(DVImportRowError(');
        sb.writeln('          row: index + 1,');
        sb.writeln('          message: error.toString(),');
        sb.writeln('        ));');
        sb.writeln('      }');
        sb.writeln('    }');
        sb.writeln(
            '    return DVImportResult<$className>(items: items, errors: errors);');
        sb.writeln('  }');
        sb.writeln();
        sb.writeln(
            '  static DVImportResult<$className> ndjson(String content) {');
        sb.writeln('    final lines = const convert.LineSplitter()');
        sb.writeln('        .convert(content)');
        sb.writeln('        .where((line) => line.trim().isNotEmpty)');
        sb.writeln('        .toList(growable: false);');
        sb.writeln('    final items = <$className>[];');
        sb.writeln('    final errors = <DVImportRowError>[];');
        sb.writeln(
            '    for (var index = 0; index < lines.length; index += 1) {');
        sb.writeln('      try {');
        sb.writeln('        final decoded = convert.jsonDecode(lines[index]);');
        sb.writeln('        if (decoded is! Map<String, dynamic>) {');
        sb.writeln(
            "          throw const FormatException('NDJSON row must be a JSON object.');");
        sb.writeln('        }');
        sb.writeln('        items.add(${className}Parser.fromJson(decoded));');
        sb.writeln('      } on Object catch (error) {');
        sb.writeln('        errors.add(DVImportRowError(');
        sb.writeln('          row: index + 1,');
        sb.writeln('          message: error.toString(),');
        sb.writeln('        ));');
        sb.writeln('      }');
        sb.writeln('    }');
        sb.writeln(
            '    return DVImportResult<$className>(items: items, errors: errors);');
        sb.writeln('  }');
        sb.writeln('}');
        sb.writeln();
        sb.writeln('/// Generated export helpers for [$className].');
        sb.writeln('class ${className}Export {');
        sb.writeln(
            '  static DVExportResult csv(Iterable<$className> items, {String fileName = \'${className.toLowerCase()}s.csv\'}) {');
        sb.writeln('    final buffer = StringBuffer();');
        sb.writeln(
            "    buffer.writeln('${fields.map((f) => f['name']!).join(',')}');");
        sb.writeln('    for (final item in items) {');
        sb.writeln('      buffer.writeln([');
        for (final field in fields) {
          final name = field['name']!;
          sb.writeln('        _escapeCsvValue(item.$name),');
        }
        sb.writeln("      ].join(','));");
        sb.writeln('    }');
        sb.writeln('    return DVExportResult(');
        sb.writeln('      fileName: fileName,');
        sb.writeln("      contentType: 'text/csv; charset=utf-8',");
        sb.writeln('      bytes: convert.utf8.encode(buffer.toString()),');
        sb.writeln('    );');
        sb.writeln('  }');
        sb.writeln();
        sb.writeln(
            '  static DVExportResult json(Iterable<$className> items, {String fileName = \'${className.toLowerCase()}s.json\'}) {');
        sb.writeln('    return DVExportResult(');
        sb.writeln('      fileName: fileName,');
        sb.writeln("      contentType: 'application/json; charset=utf-8',");
        sb.writeln(
            '      bytes: convert.utf8.encode(convert.jsonEncode(items.map((item) => item.toJson()).toList(growable: false))),');
        sb.writeln('    );');
        sb.writeln('  }');
        sb.writeln();
        sb.writeln(
            '  static DVExportResult ndjson(Iterable<$className> items, {String fileName = \'${className.toLowerCase()}s.ndjson\'}) {');
        sb.writeln('    final buffer = StringBuffer();');
        sb.writeln('    for (final item in items) {');
        sb.writeln('      buffer.writeln(convert.jsonEncode(item.toJson()));');
        sb.writeln('    }');
        sb.writeln('    return DVExportResult(');
        sb.writeln('      fileName: fileName,');
        sb.writeln("      contentType: 'application/x-ndjson; charset=utf-8',");
        sb.writeln('      bytes: convert.utf8.encode(buffer.toString()),');
        sb.writeln('    );');
        sb.writeln('  }');
        sb.writeln('}');
        sb.writeln();
        sb.writeln('/// Generated reporting helpers for [$className].');
        sb.writeln('class ${className}Report {');
        sb.writeln(
            '  static DVReportResult monthly(Iterable<$className> items, {DateTime? month}) {');
        sb.writeln('    final selectedMonth = month ?? DateTime.now();');
        sb.writeln('    return DVReportResult(');
        sb.writeln("      name: '${className.toLowerCase()}.monthly',");
        sb.writeln('      generatedAt: DateTime.now().toUtc(),');
        sb.writeln('      metrics: <String, Object?>{');
        sb.writeln("        'month': selectedMonth.month,");
        sb.writeln("        'year': selectedMonth.year,");
        sb.writeln("        'count': items.length,");
        sb.writeln('      },');
        sb.writeln('    );');
        sb.writeln('  }');
        sb.writeln('}');

        if (isSearchableModel || searchableFields.isNotEmpty) {
          final effectiveSearchableFields =
              searchableFields.isEmpty ? fields : searchableFields;
          sb.writeln();
          sb.writeln('/// Generated search facets for [$className].');
          sb.writeln('class ${className}SearchFacets {');
          for (final field in effectiveSearchableFields) {
            final type = field['type']!;
            final name = field['name']!;
            sb.writeln('  final List<$type>? $name;');
          }
          sb.writeln();
          sb.writeln('  const ${className}SearchFacets({');
          for (final field in effectiveSearchableFields) {
            final name = field['name']!;
            sb.writeln('    this.$name,');
          }
          sb.writeln('  });');
          sb.writeln('}');
          sb.writeln();
          sb.writeln('/// Generated typed search facade for [$className].');
          sb.writeln('class ${className}Search {');
          sb.writeln(
              '  static DVSearchProvider<$className, ${className}SearchFacets> _provider = const DVEmptySearchProvider<$className, ${className}SearchFacets>();');
          sb.writeln();
          sb.writeln(
              '  static void useProvider(DVSearchProvider<$className, ${className}SearchFacets> provider) {');
          sb.writeln('    _provider = provider;');
          sb.writeln('  }');
          sb.writeln();
          sb.writeln('  static Future<DVSearchResultPage<$className>> query(');
          sb.writeln('    String value, {');
          sb.writeln('    ${className}SearchFacets? facets,');
          sb.writeln('    int page = 1,');
          sb.writeln('    int perPage = 20,');
          sb.writeln('  }) {');
          sb.writeln('    return _provider.query(');
          sb.writeln('      value,');
          sb.writeln('      facets: facets,');
          sb.writeln('      page: page,');
          sb.writeln('      perPage: perPage,');
          sb.writeln('    );');
          sb.writeln('  }');
          sb.writeln('}');
        }
      }
    }

    if (classesGenerated.isNotEmpty) {
      sb.writeln();
      sb.writeln('List<String> _splitCsvLine(String line) {');
      sb.writeln("  return line.split(',').map((value) {");
      sb.writeln('    final trimmed = value.trim();');
      sb.writeln(
          "    if (trimmed.length >= 2 && trimmed.startsWith('\"') && trimmed.endsWith('\"')) {");
      sb.writeln('      return trimmed.substring(1, trimmed.length - 1);');
      sb.writeln('    }');
      sb.writeln('    return trimmed;');
      sb.writeln('  }).toList(growable: false);');
      sb.writeln('}');
      sb.writeln();
      sb.writeln('String _escapeCsvValue(Object? value) {');
      sb.writeln("  final text = value?.toString() ?? '';");
      sb.writeln(
          "  if (text.contains(',') || text.contains('\"') || text.contains('\\n')) {");
      sb.writeln(r'''    return '"${text.replaceAll('"', '""')}"';''');
      sb.writeln('  }');
      sb.writeln('  return text;');
      sb.writeln('}');
    }

    final clientDir = Directory(p.join(root, 'lib', 'dartvel_client'));
    if (!clientDir.existsSync()) {
      clientDir.createSync(recursive: true);
    }
    final sourceExports = modelImports
        .map((importLine) => importLine.replaceFirst('import ', 'export '))
        .join('\n');
    final generatedHeader =
        '// GENERATED CODE - DO NOT MODIFY BY HAND\n// ignore_for_file: directives_ordering, non_constant_identifier_names, unused_element, use_super_parameters\n// Build ID: $buildId\n';
    final content = classesGenerated.isEmpty
        ? '${generatedHeader}library dartvel_client_models;\n'
        : '$generatedHeader$sourceExports\n${modelImports.join('\n')}\n\n${sb.toString()}';
    File(p.join(clientDir.path, 'models.g.dart')).writeAsStringSync(content);
  }
}
