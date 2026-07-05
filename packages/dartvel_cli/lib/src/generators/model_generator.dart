import 'dart:io';
import 'package:glob/glob.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as p;
import '../utils/helpers.dart';

class ModelGenerator {
  static Future<void> generate({
    required String root,
    required String pkgName,
    required String buildId,
  }) async {
    final modelsDir = Directory(p.join(root, 'lib', 'models'));
    if (!modelsDir.existsSync()) {
      return;
    }

    final fs = const LocalFileSystem();
    final glob = Glob(p.join('lib', 'models', '**.dart'));
    final files = <File>[];
    for (final entity in glob.listFileSystemSync(fs, root: root, followLinks: false)) {
      if (entity is File) {
        files.add(File(entity.path));
      }
    }

    final sb = StringBuffer();
    sb.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
    sb.writeln('// Build ID: $buildId');
    sb.writeln();
    sb.writeln("import 'package:dartvel_core/dartvel.dart';");

    final modelImports = <String>[];
    final classesGenerated = <String>[];

    for (final file in files) {
      final abs = file.path;
      final rel = p.relative(abs, from: root).replaceAll('\\', '/');
      final importPath = rel.replaceFirst(RegExp(r'^lib/'), 'package:$pkgName/');
      modelImports.add("import '$importPath';");

      final content = await file.readAsString();
      // Scan for @DVModel() classes
      final classMatches = RegExp(r'@DVModel\(\)\s*class\s+([A-Za-z0-9_]+)\b').allMatches(content);
      for (final match in classMatches) {
        final className = match.group(1)!;
        classesGenerated.add(className);

        // Parse fields
        // We find all fields of format: final Type name;
        final fieldRegex = RegExp(r'final\s+([A-Za-z0-9_<>?]+)\s+([A-Za-z0-9_]+)\b');
        final fields = <Map<String, String>>[];
        for (final m in fieldRegex.allMatches(content)) {
          fields.add({
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
        sb.writeln('  /// Returns a copy of [$className] with the given fields replaced.');
        final params = fields.map((f) => "${f['type']}? ${f['name']}").join(', ');
        sb.writeln('  $className copyWith({$params}) {');
        sb.writeln('    return $className(');
        for (final field in fields) {
          final name = field['name']!;
          sb.writeln("      $name: $name ?? this.$name,");
        }
        sb.writeln('    );');
        sb.writeln('  }');

        // Database metadata
        final tableName = className.toLowerCase() + 's';
        sb.writeln();
        sb.writeln("  /// Database table name for [$className].");
        sb.writeln("  String get tableName => '$tableName';");
        sb.writeln();
        sb.writeln("  /// SQL statement to create the [$className] table.");
        final cols = fields.map((f) => "${f['name']} TEXT").join(', ');
        sb.writeln("  String get createTableSql => 'CREATE TABLE IF NOT EXISTS $tableName ($cols)';");

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
      }
    }

    if (classesGenerated.isNotEmpty) {
      final header = modelImports.join('\n') + '\n\n' + sb.toString();
      final clientDir = Directory(p.join(root, 'lib', 'dartvel_client'));
      if (!clientDir.existsSync()) {
        clientDir.createSync(recursive: true);
      }
      File(p.join(clientDir.path, 'models.g.dart')).writeAsStringSync(header);
    }
  }
}
