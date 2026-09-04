/// An API description becoming Dartvel models and a typed client.
///
/// Dartvel already writes an OpenAPI document out of an application. Reading
/// one in is the other direction, and the one people actually start from: an
/// API exists, somebody hands you its spec, and the work is transcribing it
/// into models and calls by hand.
///
/// What comes out is ordinary Dartvel source — private `@DVModel` inputs and
/// a function per operation — so the import is a starting point rather than a
/// dependency. Nothing here runs at build time and nothing reads the spec
/// again.
library;

import 'dart:convert';

import 'import_names.dart';

/// What an import produced.
class DVOpenApiImport {
  const DVOpenApiImport({required this.sources, required this.problems});

  /// Path to Dart source.
  final Map<String, String> sources;

  /// What could not be read, named precisely.
  ///
  /// A field of an unknown shape typed as `dynamic` would compile and lose
  /// the error where nobody looks for it, so it is reported instead.
  final List<String> problems;
}

/// Reads an OpenAPI document.
///
/// Throws [FormatException] when the document is not JSON: "import failed"
/// against a four-thousand-line file is not something anybody can act on.
DVOpenApiImport dvImportOpenApi(String document) {
  final Object? decoded = jsonDecode(document);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('An OpenAPI document is a JSON object.');
  }

  final List<String> problems = <String>[];
  final Map<String, String> sources = <String, String>{};

  final Object? components = decoded['components'];
  final Object? rawSchemas =
      components is Map ? components['schemas'] : null;
  final Map<String, Object?> schemas =
      rawSchemas is Map ? rawSchemas.cast<String, Object?>() : <String, Object?>{};

  for (final MapEntry<String, Object?> entry in schemas.entries) {
    if (entry.value is! Map) continue;
    final String name = dvImportClassName(entry.key);
    sources['lib/models/${dvImportFileName(entry.key)}.dart'] = _modelSource(
      name,
      entry.value! as Map<Object?, Object?>,
      schemas,
      problems,
    );
  }

  final Object? info = decoded['info'];
  final String title = info is Map ? '${info['title'] ?? 'api'}' : 'api';
  final Object? paths = decoded['paths'];
  if (paths is Map) {
    sources['lib/api/${dvImportFileName(title)}.dart'] =
        _clientSource(title, paths.cast<String, Object?>(), schemas, problems);
  }

  return DVOpenApiImport(sources: sources, problems: problems);
}

const Set<String> _methods = <String>{
  'get',
  'post',
  'put',
  'patch',
  'delete',
  'head',
  'options',
};

String _modelSource(
  String name,
  Map<Object?, Object?> schema,
  Map<String, Object?> schemas,
  List<String> problems,
) {
  final Object? rawProperties = schema['properties'];
  final Map<String, Object?> properties = rawProperties is Map
      ? rawProperties.cast<String, Object?>()
      : <String, Object?>{};
  final Set<String> required = <String>{
    for (final Object? entry in schema['required'] is List
        ? schema['required']! as List<Object?>
        : const <Object?>[])
      '$entry',
  };

  final StringBuffer out = StringBuffer()
    ..writeln("import 'package:dartvel_core/dartvel.dart';")
    ..writeln()
    ..writeln('// Imported from an OpenAPI document. Ordinary source: edit it,')
    ..writeln('// rename it, delete what the application does not use.')
    ..writeln('@DVModel()')
    ..writeln('class _$name {');

  final List<String> fields = <String>[];
  properties.forEach((String property, Object? definition) {
    if (definition is! Map) return;
    final String? type = _dartType(definition, schemas, problems,
        where: '$name.$property');
    if (type == null) return;
    final String field = dvImportFieldName(property);
    // A field the API may omit and the model insists on is a parse that
    // throws on the first response that leaves it out.
    final String declared = required.contains(property) ? type : '$type?';
    out.writeln('  final $declared $field;');
    fields.add('this.$field');
  });

  out
    ..writeln()
    ..writeln('  const _$name(${fields.isEmpty ? '' : '{${fields.join(', ')}}'});')
    ..writeln('}');
  return out.toString();
}

String _clientSource(
  String title,
  Map<String, Object?> paths,
  Map<String, Object?> schemas,
  List<String> problems,
) {
  final StringBuffer out = StringBuffer()
    ..writeln("import 'package:dartvel_core/dartvel.dart';")
    ..writeln()
    ..writeln('// Imported from an OpenAPI document: one function per')
    ..writeln('// operation, calling the API as it describes itself.')
    ..writeln('//')
    ..writeln('// These are ordinary functions. Annotate one with')
    ..writeln('// @DVBackendFunction to serve it from this application')
    ..writeln('// instead, or leave them as the client they are.');

  paths.forEach((String path, Object? operations) {
    if (operations is! Map) return;
    operations.forEach((Object? method, Object? operation) {
      final String verb = '$method'.toLowerCase();
      if (!_methods.contains(verb) || operation is! Map) return;

      final String name = operation['operationId'] is String
          ? dvImportMethodName('${operation['operationId']}')
          : dvImportMethodName('$verb ${path.replaceAll(RegExp('[{}]'), '')}');
      final String returns =
          _responseType(operation, schemas, problems, where: name) ?? 'void';

      final List<String> arguments = <String>[];
      for (final Object? raw in operation['parameters'] is List
          ? operation['parameters']! as List<Object?>
          : const <Object?>[]) {
        if (raw is! Map || raw['in'] != 'path') continue;
        final Object? schema = raw['schema'];
        final String type = schema is Map
            ? _dartType(schema, schemas, problems, where: name) ?? 'String'
            : 'String';
        arguments.add('$type ${dvImportFieldName('${raw['name']}')}');
      }

      // The path with its parameters interpolated. A generated call that
      // asks for an id and then requests /products/{id} literally is the
      // failure this avoids.
      final String interpolated =
          path.replaceAllMapped(RegExp(r'\{([^}]+)\}'), (Match m) {
        return '\$${dvImportFieldName(m.group(1)!)}';
      });

      out
        ..writeln()
        ..writeln('/// `${verb.toUpperCase()} $path`')
        ..writeln('Future<$returns> $name(${arguments.join(', ')}) async {')
        ..writeln("  final DVHttpResponse response = await DV.Http.$verb('$interpolated');")
        ..writeln(_returnStatement(returns))
        ..writeln('}');
    });
  });
  return out.toString();
}

String _returnStatement(String returns) {
  if (returns == 'void') return '  // Nothing to read: the operation returns no content.';
  final RegExpMatch? list = RegExp(r'^List<(.+)>$').firstMatch(returns);
  if (list != null) {
    return '  return <${list.group(1)}>[\n'
        '    for (final Object? item in response.json as List<Object?>)\n'
        '      ${list.group(1)}.fromJson(item! as Map<String, Object?>),\n'
        '  ];';
  }
  if (const <String>['String', 'int', 'double', 'num', 'bool'].contains(returns)) {
    return '  return response.json as $returns;';
  }
  return '  return $returns.fromJson(response.json as Map<String, Object?>);';
}

/// The Dart type for a schema, or null when it cannot be read.
String? _dartType(
  Map<Object?, Object?> schema,
  Map<String, Object?> schemas,
  List<String> problems, {
  required String where,
}) {
  final Object? reference = schema[r'$ref'];
  if (reference is String) {
    final String name = reference.split('/').last;
    if (!schemas.containsKey(name)) {
      problems.add('$where refers to a schema named "$name", and the document '
          'defines no such schema.');
      return null;
    }
    return dvImportClassName(name);
  }

  final String type = '${schema['type'] ?? ''}';
  final String format = '${schema['format'] ?? ''}';
  switch (type) {
    case 'string':
      return format == 'date-time' ? 'DateTime' : 'String';
    case 'integer':
      return 'int';
    case 'number':
      return 'double';
    case 'boolean':
      return 'bool';
    case 'array':
      final Object? items = schema['items'];
      if (items is! Map) {
        problems.add('$where is an array and says nothing about its items.');
        return null;
      }
      final String? inner =
          _dartType(items, schemas, problems, where: '$where[]');
      return inner == null ? null : 'List<$inner>';
    case 'object':
      return 'Map<String, Object?>';
    default:
      problems.add('$where has no type this import can read'
          '${type.isEmpty ? '' : ' ("$type")'}.');
      return null;
  }
}

String? _responseType(
  Map<Object?, Object?> operation,
  Map<String, Object?> schemas,
  List<String> problems, {
  required String where,
}) {
  final Object? responses = operation['responses'];
  if (responses is! Map) return null;
  for (final String code in const <String>['200', '201', 'default']) {
    final Object? response = responses[code];
    if (response is! Map) continue;
    final Object? content = response['content'];
    if (content is! Map) continue;
    final Object? json = content['application/json'];
    if (json is! Map) continue;
    final Object? schema = json['schema'];
    if (schema is! Map) continue;
    return _dartType(schema, schemas, problems, where: where);
  }
  return null;
}

