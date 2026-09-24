/// An OpenAPI document becomes a Dartvel module.
///
/// The cheapest rung in *Module Sources*: a described API produces a **pure
/// Dart module**, with no foreign runtime, no artifact and no binding of any
/// kind. What comes out is a Dart package the parent mounts like any other,
/// whose calls go over `DV.Http` against a host the module declares -- so the
/// retries, timeouts, circuit breaking and secret resolution are the ones the
/// specification already defines rather than a second set written here.
///
/// It refuses rather than guesses. A document describing something this
/// cannot express is a refusal naming what it was, because a generated method
/// that compiles and sends the wrong request is the failure nobody finds.
library;

import 'described_api.dart';

export 'described_api.dart' show DVDescribedApiRefused, DVGeneratedModule;

/// Generates the module for [document].
///
/// [moduleId] is what the parent will call it. [host] defaults to the module
/// id, so a module and the host it talks to have one name unless a project
/// already uses that name for something else.
DVGeneratedModule dvGenerateDescribedApiModule({
  required Map<String, Object?> document,
  required String moduleId,
  String? host,
  String? baseUrl,
}) {
  final String version = '${document['openapi'] ?? ''}';
  if (!version.startsWith('3.')) {
    throw DVDescribedApiRefused(
      version.isEmpty
          ? 'This is not an OpenAPI document: it declares no openapi version. '
              'Swagger 2.0 documents convert with an upstream tool first.'
          : 'OpenAPI $version is not a version this reads. It is written '
              'against OpenAPI 3.x; a 2.0 document converts with an upstream '
              'tool first.',
    );
  }

  final List<Object?> servers =
      document['servers'] is List ? document['servers']! as List<Object?> : const <Object?>[];
  // What was asked for wins over what the document says: a document
  // published with its production server is used against a staging one by
  // saying so, rather than by editing somebody else's file.
  final String? resolvedBase = baseUrl ??
      (servers.isEmpty
          ? null
          : (servers.first is Map
              ? '${(servers.first! as Map)['url'] ?? ''}'
              : null));
  if (resolvedBase == null || resolvedBase.isEmpty) {
    throw const DVDescribedApiRefused(
      'The document declares no servers, so there is no base URL to declare '
      'the host with. Add servers: to the document, or a dartvel.http.hosts '
      'entry by hand and pass --host.',
    );
  }

  final String hostName = host ?? moduleId;
  final String packageName = dvSnake(moduleId);
  final _Schemas schemas = _Schemas.of(document);
  final List<_Operation> operations = _operationsOf(document, schemas);

  return DVGeneratedModule(
    id: moduleId,
    packageName: packageName,
    host: hostName,
    files: <String, String>{
      'pubspec.yaml': dvDescribedApiPubspec(
        packageName: packageName,
        moduleId: moduleId,
        hostName: hostName,
        baseUrl: resolvedBase,
        title: '${(document['info'] as Map?)?['title'] ?? moduleId}',
        from: 'an OpenAPI document',
      ),
      'lib/$packageName.dart': _library(
        packageName: packageName,
        moduleId: moduleId,
        hostName: hostName,
        title: '${(document['info'] as Map?)?['title'] ?? moduleId}',
        operations: operations,
        schemas: schemas,
      ),
    },
  );
}

/// The document's component schemas, and what a reference to one resolves to.
class _Schemas {
  _Schemas(this.byName);

  factory _Schemas.of(Map<String, Object?> document) {
    final Object? components = document['components'];
    final Object? schemas = components is Map ? components['schemas'] : null;
    if (schemas is! Map) return _Schemas(const <String, Map<String, Object?>>{});
    // Sorted, so the generated file does not depend on the order a YAML
    // parser happened to hand back.
    final List<String> names = schemas.keys.map((Object? k) => '$k').toList()
      ..sort();
    return _Schemas(<String, Map<String, Object?>>{
      for (final String name in names)
        name: (schemas[name] as Map).cast<String, Object?>(),
    });
  }

  final Map<String, Map<String, Object?>> byName;

  /// The class name a `$ref` points at, checked against what the document
  /// actually defines.
  String resolve(String ref) {
    const String prefix = '#/components/schemas/';
    if (!ref.startsWith(prefix)) {
      throw DVDescribedApiRefused(
        '"$ref" is a reference this does not follow. Only '
        '$prefix<name> references within the document are read; a reference '
        'to another file or a URL has to be bundled into one document first.',
      );
    }
    final String name = ref.substring(prefix.length);
    if (!byName.containsKey(name)) {
      throw DVDescribedApiRefused(
        '"$ref" names a schema the document does not define. It defines: '
        '${byName.keys.isEmpty ? 'none' : byName.keys.join(', ')}.',
      );
    }
    return dvClassName(name);
  }
}

/// One call: everything the generated method needs.
class _Operation {
  const _Operation({
    required this.name,
    required this.method,
    required this.path,
    required this.pathParameters,
    required this.queryParameters,
    required this.bodyType,
    required this.bodyRequired,
    required this.returnType,
  });

  final String name;
  final String method;
  final String path;
  final List<_Parameter> pathParameters;
  final List<_Parameter> queryParameters;
  final String? bodyType;
  final bool bodyRequired;

  /// The Dart type the method answers with, or null for a call whose
  /// response this cannot type -- which is `void` rather than a guess.
  final String? returnType;
}

class _Parameter {
  const _Parameter(this.name, this.type, {required this.required});

  final String name;
  final String type;
  final bool required;

  /// The Dart identifier, which is the wire name unless that is not one.
  String get identifier => dvCamel(name);
}

List<_Operation> _operationsOf(Map<String, Object?> document, _Schemas schemas) {
  final Object? paths = document['paths'];
  if (paths is! Map) return const <_Operation>[];
  const List<String> methods = <String>[
    'get',
    'put',
    'post',
    'delete',
    'patch',
    'head',
  ];
  final List<_Operation> out = <_Operation>[];
  final Map<String, String> claimed = <String, String>{};
  // Sorted by path, then by the method order above, so the generated file is
  // the same whichever order the document was written in.
  final List<String> pathNames = paths.keys.map((Object? k) => '$k').toList()
    ..sort();
  for (final String path in pathNames) {
    final Object? item = paths[path];
    if (item is! Map) continue;
    final Object? shared = item['parameters'];
    for (final String method in methods) {
      final Object? operation = item[method];
      if (operation is! Map) continue;
      final Map<String, Object?> op = operation.cast<String, Object?>();
      final String name = op['operationId'] is String &&
              '${op['operationId']}'.trim().isNotEmpty
          ? dvCamel('${op['operationId']}')
          : _nameFor(method, path);
      final String? previous = claimed[name];
      if (previous != null) {
        throw DVDescribedApiRefused(
          '$previous and ${method.toUpperCase()} $path both generate '
          '$name(). Give one of them a distinct operationId: keeping one of '
          'the two would drop a call the document describes.',
        );
      }
      claimed[name] = '${method.toUpperCase()} $path';

      final List<_Parameter> pathParameters = <_Parameter>[];
      final List<_Parameter> queryParameters = <_Parameter>[];
      for (final Object? entry in <Object?>[
        ...shared is List ? shared : const <Object?>[],
        ...op['parameters'] is List
            ? op['parameters']! as List<Object?>
            : const <Object?>[],
      ]) {
        if (entry is! Map) continue;
        final String where = '${entry['in'] ?? ''}';
        if (where != 'path' && where != 'query') continue;
        final String wire = '${entry['name'] ?? ''}';
        if (wire.isEmpty) continue;
        final _Parameter parameter = _Parameter(
          wire,
          _dartType(entry['schema'], schemas),
          // A path parameter is required whatever the document says: the
          // path cannot be built without it.
          required: where == 'path' || entry['required'] == true,
        );
        (where == 'path' ? pathParameters : queryParameters).add(parameter);
      }
      // Every `{name}` in the path has to be an argument, or the generated
      // method builds a URL with a brace in it and the call reaches nothing.
      for (final RegExpMatch match
          in RegExp(r'\{([^}]+)\}').allMatches(path)) {
        final String wire = match.group(1)!;
        if (pathParameters.any((_Parameter p) => p.name == wire)) continue;
        throw DVDescribedApiRefused(
          '${method.toUpperCase()} $path takes {$wire} in its path and the '
          'document declares no parameter for it, so there is nothing to put '
          'there.',
        );
      }

      out.add(_Operation(
        name: name,
        method: method.toUpperCase(),
        path: path,
        pathParameters: pathParameters,
        queryParameters: queryParameters,
        bodyType: _bodyTypeOf(op['requestBody'], schemas),
        bodyRequired: op['requestBody'] is Map &&
            (op['requestBody']! as Map)['required'] == true,
        returnType: _responseTypeOf(op['responses'], schemas),
      ));
    }
  }
  return out;
}

String? _bodyTypeOf(Object? requestBody, _Schemas schemas) {
  if (requestBody is! Map) return null;
  final Object? content = requestBody['content'];
  if (content is! Map) return null;
  final Object? json = content['application/json'];
  if (json is! Map) return null;
  final String type = _dartType(json['schema'], schemas);
  return type == 'Object?' ? null : type;
}

String? _responseTypeOf(Object? responses, _Schemas schemas) {
  if (responses is! Map) return null;
  // The first success the document describes, in numeric order, so a
  // document listing 200 and 201 does not depend on which came first.
  final List<String> codes = responses.keys
      .map((Object? k) => '$k')
      .where((String code) => code.startsWith('2'))
      .toList()
    ..sort();
  for (final String code in codes) {
    final Object? response = responses[code];
    if (response is! Map) continue;
    final Object? content = response['content'];
    if (content is! Map) continue;
    final Object? json = content['application/json'];
    if (json is! Map) continue;
    final String type = _dartType(json['schema'], schemas);
    if (type != 'Object?') return type;
  }
  return null;
}

/// The Dart type for one schema node.
String _dartType(Object? schema, _Schemas schemas) {
  if (schema is! Map) return 'Object?';
  final Object? ref = schema[r'$ref'];
  if (ref is String) return schemas.resolve(ref);
  switch ('${schema['type'] ?? ''}') {
    case 'string':
      return 'String';
    case 'integer':
      return 'int';
    case 'number':
      return 'double';
    case 'boolean':
      return 'bool';
    case 'array':
      final String item = _dartType(schema['items'], schemas);
      return 'List<${item == 'Object?' ? 'Object?' : item}>';
    default:
      return 'Object?';
  }
}


String _library({
  required String packageName,
  required String moduleId,
  required String hostName,
  required String title,
  required List<_Operation> operations,
  required _Schemas schemas,
}) {
  final String className = '${dvClassName(moduleId)}Api';
  final StringBuffer out = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
    ..writeln('//')
    ..writeln('// $title, read from its OpenAPI document by dartvel add.')
    ..writeln('// Regenerate it rather than editing it: dartvel add refuses a')
    ..writeln('// wrapper it did not write, and an edit here is lost on the')
    ..writeln('// next refresh (DV-MODULE-016).')
    ..writeln('library $packageName;')
    ..writeln()
    ..writeln("import 'package:dartvel_core/dartvel.dart';")
    ..writeln()
    ..write(dvDescribedApiExceptionSource(moduleId))
    ..writeln()
    ..writeln('/// $title.')
    ..writeln('///')
    ..writeln('/// Every call goes to the `$hostName` host declared in this')
    ..writeln("/// package's pubspec, so a base URL, a credential, a retry")
    ..writeln('/// policy and a timeout are configuration rather than code.')
    ..writeln('class $className {')
    ..writeln('  const $className();')
    ..writeln()
    ..writeln('  /// The declared host these calls go to.')
    ..writeln("  static const String host = '$hostName';")
    ..writeln();

  for (final _Operation operation in operations) {
    _writeOperation(out, operation, moduleId);
  }
  out.writeln('}');

  for (final MapEntry<String, Map<String, Object?>> entry
      in schemas.byName.entries) {
    out.writeln();
    _writeSchema(out, entry.key, entry.value, schemas);
  }
  return out.toString();
}

void _writeOperation(StringBuffer out, _Operation op, String moduleId) {
  final List<String> arguments = <String>[
    for (final _Parameter p in op.pathParameters)
      'required ${p.type} ${p.identifier}',
    if (op.bodyType != null)
      op.bodyRequired ? 'required ${op.bodyType} body' : '${op.bodyType}? body',
    for (final _Parameter p in op.queryParameters)
      p.required
          ? 'required ${p.type} ${p.identifier}'
          : '${p.type}? ${p.identifier}',
  ];
  final String returns = op.returnType ?? 'void';

  // The path with each {name} replaced by the encoded argument. Encoded
  // rather than interpolated: a value holding a slash is a different
  // endpoint, and the call would succeed against it.
  String path = op.path;
  for (final _Parameter p in op.pathParameters) {
    // A String goes in as it stands; anything else is interpolated first,
    // because encodeComponent takes a String. '$x' around a String is an
    // interpolation the analyzer calls unnecessary, and generated code has
    // to analyze clean or every project carrying it does not.
    final String value =
        p.type == 'String' ? p.identifier : "'\$${p.identifier}'";
    path = path.replaceAll(
      '{${p.name}}',
      '\${Uri.encodeComponent($value)}',
    );
  }

  out
    ..writeln('  /// `${op.method} ${op.path}`')
    ..writeln('  Future<$returns> ${op.name}('
        '${arguments.isEmpty ? '' : '{${arguments.join(', ')}}'}) async {');
  if (op.queryParameters.isEmpty) {
    out.writeln("    final String path = '$path';");
  } else {
    out
      ..writeln('    final Map<String, String> query = <String, String>{')
      ..writeln(op.queryParameters.map((_Parameter p) {
        // A String goes in as it stands: '$value' around one is an
        // interpolation the analyzer calls unnecessary, and generated code
        // has to analyze clean or every project carrying it does not.
        final String value =
            p.type == 'String' ? p.identifier : "'\$${p.identifier}'";
        return p.required
            ? "      '${p.name}': $value,"
            : "      if (${p.identifier} != null) '${p.name}': $value,";
      }).join('\n'))
      ..writeln('    };')
      ..writeln("    final String path = query.isEmpty")
      ..writeln("        ? '$path'")
      ..writeln("        : '$path?\${Uri(queryParameters: query).query}';");
  }
  final String call = op.bodyType == null
      ? "const DVHttp().host(host).send('${op.method}', path)"
      : op.bodyRequired
          ? "const DVHttp().host(host)"
              ".send('${op.method}', path, json: body.toJson())"
          : "const DVHttp().host(host)"
              ".send('${op.method}', path, json: body?.toJson())";
  out
    ..writeln('    final Response response = await $call;')
    ..writeln('    if (response.status < 200 || response.status >= 300) {')
    ..writeln('      throw ${dvClassName(moduleId)}Exception('
        "'${op.method} ${op.path}', response.status);")
    ..writeln('    }');
  if (op.returnType == null) {
    out
      ..writeln('    return;')
      ..writeln('  }')
      ..writeln();
    return;
  }
  out.writeln('    final Object? decoded = '
      'await response.body?.jsonDecode();');
  if (op.returnType!.startsWith('List<')) {
    final String item =
        op.returnType!.substring(5, op.returnType!.length - 1);
    out
      ..writeln('    if (decoded is! List) {')
      ..writeln('      throw ${dvClassName(moduleId)}Exception('
          "'${op.method} ${op.path}', response.status);")
      ..writeln('    }')
      ..writeln('    return <$item>[')
      ..writeln('      for (final Object? entry in decoded)')
      ..writeln('        ${_decode(item, 'entry')},')
      ..writeln('    ];');
  } else {
    out
      ..writeln('    if (decoded is! Map) {')
      ..writeln('      throw ${dvClassName(moduleId)}Exception('
          "'${op.method} ${op.path}', response.status);")
      ..writeln('    }')
      ..writeln('    return ${op.returnType}.fromJson('
          'decoded.cast<String, Object?>());');
  }
  out
    ..writeln('  }')
    ..writeln();
}

/// The expression that turns one decoded JSON value into [type].
String _decode(String type, String value) => switch (type) {
      'String' || 'int' || 'double' || 'bool' => '$value! as $type',
      'Object?' => value,
      _ => '$type.fromJson(($value! as Map).cast<String, Object?>())',
    };

void _writeSchema(
  StringBuffer out,
  String name,
  Map<String, Object?> schema,
  _Schemas schemas,
) {
  final String className = dvClassName(name);
  final Object? properties = schema['properties'];
  final Set<String> required = <String>{
    for (final Object? entry
        in schema['required'] is List ? schema['required']! as List<Object?> : const <Object?>[])
      '$entry',
  };
  final List<({String wire, String identifier, String type, bool required})>
      fields = <({String wire, String identifier, String type, bool required})>[];
  if (properties is Map) {
    final List<String> names =
        properties.keys.map((Object? k) => '$k').toList()..sort();
    for (final String wire in names) {
      fields.add((
        wire: wire,
        identifier: dvCamel(wire),
        type: _dartType(properties[wire], schemas),
        required: required.contains(wire),
      ));
    }
  }

  out
    ..writeln('/// `$name`, as the document describes it.')
    ..writeln('class $className {')
    ..writeln('  const $className({');
  for (final ({String wire, String identifier, String type, bool required}) f
      in fields) {
    out.writeln('    ${f.required ? 'required ' : ''}this.${f.identifier},');
  }
  out
    ..writeln('  });')
    ..writeln();

  out.writeln('  factory $className.fromJson(Map<String, Object?> json) =>');
  out.writeln('      $className(');
  for (final ({String wire, String identifier, String type, bool required}) f
      in fields) {
    out.writeln('        ${f.identifier}: '
        '${_fromJson(f.type, "json['${f.wire}']", required: f.required)},');
  }
  out
    ..writeln('      );')
    ..writeln();

  for (final ({String wire, String identifier, String type, bool required}) f
      in fields) {
    out.writeln('  final ${f.type}${f.required ? '' : '?'} ${f.identifier};');
  }
  out
    ..writeln()
    ..writeln('  Map<String, Object?> toJson() => <String, Object?>{');
  for (final ({String wire, String identifier, String type, bool required}) f
      in fields) {
    final String value = _toJson(f.type, f.identifier, required: f.required);
    out.writeln(f.required
        ? "        '${f.wire}': $value,"
        : "        if (${f.identifier} != null) '${f.wire}': $value,");
  }
  out
    ..writeln('      };')
    ..writeln('}');
}

/// The expression that reads one field out of a decoded map.
String _fromJson(String type, String access, {required bool required}) {
  if (type.startsWith('List<')) {
    final String item = type.substring(5, type.length - 1);
    final String each = _decode(item, 'entry');
    final String list = '<$item>[for (final Object? entry in '
        '($access! as List)) $each]';
    return required ? list : '$access == null ? null : $list';
  }
  switch (type) {
    case 'String':
    case 'int':
    case 'double':
    case 'bool':
      return required ? '$access! as $type' : '$access as $type?';
    case 'Object?':
      return access;
    default:
      final String read =
          '$type.fromJson(($access! as Map).cast<String, Object?>())';
      return required ? read : '$access == null ? null : $read';
  }
}

/// The expression that writes one field back out.
String _toJson(String type, String identifier, {required bool required}) {
  if (type.startsWith('List<')) {
    final String item = type.substring(5, type.length - 1);
    if (const <String>{'String', 'int', 'double', 'bool', 'Object?'}
        .contains(item)) {
      return identifier;
    }
    return '[for (final $item entry in $identifier) entry.toJson()]';
  }
  if (const <String>{'String', 'int', 'double', 'bool', 'Object?'}
      .contains(type)) {
    return identifier;
  }
  return '$identifier${required ? '' : '!'}.toJson()';
}

/// `get` + the path's own words: `GET /orders/{id}/lines` is `getOrdersLines`.
///
/// Only reached when the document names no operationId. It leaves the
/// parameters out, because `{id}` is an argument rather than part of the
/// name, and two paths differing only in a parameter name are the same call.
String _nameFor(String method, String path) {
  final Iterable<String> words = path
      .split('/')
      .where((String part) => part.isNotEmpty && !part.startsWith('{'))
      .map(dvWords)
      .expand((List<String> parts) => parts);
  return dvCamel('$method ${words.join(' ')}');
}





