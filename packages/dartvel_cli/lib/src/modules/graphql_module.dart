/// A GraphQL schema becomes a Dartvel module.
///
/// The same outcome as an OpenAPI document: a **pure Dart module**, calls
/// over `DV.Http`, no binding and no foreign runtime. What is different is
/// that a schema is a graph and a request carries a selection, so the
/// generated types have to say exactly what was asked for.
///
/// That is why the result classes are per operation rather than per schema
/// type. A shared `Customer` class would carry every field the type has, and
/// a query that selected three of them would hand back an object whose other
/// fields are null because nothing asked -- indistinguishable from a service
/// that answered null. A class written from the selection cannot lie that
/// way: a field that was not selected is not on it.
///
/// Where the graph turns back on itself the walk stops, the selection omits
/// the field and the class does not declare it, with a comment saying which
/// type it returned to. An infinite selection is not a thing to guess a depth
/// for.
library;

import 'described_api.dart';

/// Generates the module for [schema], an SDL document.
///
/// [url] is the endpoint: its origin becomes the declared host's base URL and
/// its path becomes the one path every call posts to.
DVGeneratedModule dvGenerateGraphQlModule({
  required String schema,
  required String moduleId,
  required String url,
  String? host,
}) {
  final Uri? endpoint = Uri.tryParse(url);
  if (endpoint == null || !endpoint.hasScheme || !endpoint.hasAuthority) {
    throw DVDescribedApiRefused(
      '"$url" is not an endpoint. A GraphQL schema does not name its own '
      'server, so the URL to post to has to be given: pass --url with the '
      'full endpoint, such as https://api.vendor.com/graphql.',
    );
  }

  final _Schema parsed = _parse(schema);
  final String hostName = host ?? moduleId;
  final String packageName = dvSnake(moduleId);

  return DVGeneratedModule(
    id: moduleId,
    packageName: packageName,
    host: hostName,
    files: <String, String>{
      'pubspec.yaml': dvDescribedApiPubspec(
        packageName: packageName,
        moduleId: moduleId,
        hostName: hostName,
        // The origin alone. Uri.replace leaves a bare "?" behind, and a
        // base URL ending in one is a base URL every path is appended to
        // after a query separator.
        baseUrl: '${endpoint.scheme}://${endpoint.authority}',
        title: moduleId,
        from: 'a GraphQL schema',
      ),
      'lib/$packageName.dart': _library(
        packageName: packageName,
        moduleId: moduleId,
        hostName: hostName,
        path: endpoint.path.isEmpty ? '/graphql' : endpoint.path,
        schema: parsed,
      ),
    },
  );
}

// --------------------------------------------------------------------------
// The schema, as much of it as a generated client needs.
// --------------------------------------------------------------------------

class _Schema {
  _Schema({
    required this.types,
    required this.inputs,
    required this.enums,
    required this.scalars,
    required this.queryType,
    required this.mutationType,
  });

  final Map<String, _Type> types;
  final Map<String, _Type> inputs;
  final Map<String, List<String>> enums;
  final Set<String> scalars;
  final String queryType;
  final String? mutationType;
}

class _Type {
  _Type(this.name, this.fields);

  final String name;
  final List<_Field> fields;
}

class _Field {
  _Field(this.name, this.type, this.arguments);

  final String name;
  final _Ref type;
  final List<_Argument> arguments;
}

class _Argument {
  _Argument(this.name, this.type);

  final String name;
  final _Ref type;
}

/// A type reference: a name, wrapped in any number of lists, each part either
/// nullable or not.
class _Ref {
  _Ref(this.name, {required this.nonNull, this.of});

  /// The named type at the bottom, whatever the wrapping.
  final String name;
  final bool nonNull;

  /// The element, for a list.
  final _Ref? of;

  bool get isList => of != null;

  /// How it is written back into a document, for a variable declaration.
  String get sdl {
    final String inner = isList ? '[${of!.sdl}]' : name;
    return nonNull ? '$inner!' : inner;
  }
}

// --------------------------------------------------------------------------
// Parsing. A small reader for the part of SDL a client is generated from.
// --------------------------------------------------------------------------

_Schema _parse(String source) {
  final _Reader reader = _Reader(source);
  final Map<String, _Type> types = <String, _Type>{};
  final Map<String, _Type> inputs = <String, _Type>{};
  final Map<String, List<String>> enums = <String, List<String>>{};
  final Set<String> scalars = <String>{};
  String? declaredQuery;
  String? declaredMutation;
  String? declaredSubscription;

  while (!reader.atEnd) {
    reader.skipDescription();
    if (reader.atEnd) break;
    final String keyword = reader.name();
    switch (keyword) {
      case 'schema':
        reader.expect('{');
        while (!reader.take('}')) {
          final String role = reader.name();
          reader.expect(':');
          final String named = reader.name();
          reader.take(',');
          switch (role) {
            case 'query':
              declaredQuery = named;
            case 'mutation':
              declaredMutation = named;
            case 'subscription':
              declaredSubscription = named;
          }
        }
      case 'type':
        final _Type type = reader.objectType();
        types[type.name] = type;
      case 'input':
        final _Type type = reader.objectType();
        inputs[type.name] = type;
      case 'enum':
        final String name = reader.name();
        reader.skipDirectives();
        reader.expect('{');
        final List<String> values = <String>[];
        while (!reader.take('}')) {
          reader.skipDescription();
          values.add(reader.name());
          reader.skipDirectives();
          reader.take(',');
        }
        enums[name] = values;
      case 'scalar':
        scalars.add(reader.name());
        reader.skipDirectives();
      case 'interface':
      case 'union':
      case 'extend':
        throw DVDescribedApiRefused(
          'This schema declares a $keyword, and a client generated from a '
          'schema alone cannot select through one: an interface or a union '
          'needs a fragment per concrete type, which is a choice about the '
          'call rather than about the schema. Nothing was written.',
        );
      case 'directive':
        reader.skipToTopLevel();
      default:
        throw DVDescribedApiRefused(
          '"$keyword" is not a definition this reads. It reads schema, type, '
          'input, enum, scalar and directive.',
        );
    }
  }

  if (declaredSubscription != null) {
    throw const DVDescribedApiRefused(
      'This schema declares a subscription type. A subscription is a stream '
      'over a socket and not a request over HTTP, so a module generated from '
      'this would be one whose calls could not be made. Nothing was written.',
    );
  }

  final String query = declaredQuery ?? 'Query';
  if (!types.containsKey(query)) {
    throw DVDescribedApiRefused(
      declaredQuery == null
          ? 'This schema defines no Query type, so there is nothing to call. '
              'A schema block naming another type works too.'
          : 'The schema block names $query as its query type and the '
              'document does not define it.',
    );
  }
  if (declaredMutation != null && !types.containsKey(declaredMutation)) {
    throw DVDescribedApiRefused(
      'The schema block names $declaredMutation as its mutation type and the '
      'document does not define it.',
    );
  }
  final String? mutation = declaredMutation ??
      (types.containsKey('Mutation') ? 'Mutation' : null);

  final _Schema parsed = _Schema(
    types: types,
    inputs: inputs,
    enums: enums,
    scalars: scalars,
    queryType: query,
    mutationType: mutation,
  );
  _checkEveryTypeExists(parsed);
  return parsed;
}

/// Every named type a field or an argument mentions is one the document
/// defines, so a generated method cannot reference a Dart class nothing
/// wrote.
void _checkEveryTypeExists(_Schema schema) {
  void check(String where, _Ref ref) {
    if (_builtInScalars.containsKey(ref.name)) return;
    if (schema.scalars.contains(ref.name)) return;
    if (schema.enums.containsKey(ref.name)) return;
    if (schema.types.containsKey(ref.name)) return;
    if (schema.inputs.containsKey(ref.name)) return;
    throw DVDescribedApiRefused(
      '$where refers to ${ref.name} and the document does not define it. A '
      'schema that leans on another document has to be assembled into one '
      'first.',
    );
  }

  for (final _Type type in <_Type>[
    ...schema.types.values,
    ...schema.inputs.values,
  ]) {
    for (final _Field field in type.fields) {
      check('${type.name}.${field.name}', field.type);
      for (final _Argument argument in field.arguments) {
        check('${type.name}.${field.name}(${argument.name}:)', argument.type);
      }
    }
  }
}

/// A reader over the document's tokens.
class _Reader {
  _Reader(this.source);

  final String source;
  int offset = 0;

  bool get atEnd {
    _skipTrivia();
    return offset >= source.length;
  }

  void _skipTrivia() {
    while (offset < source.length) {
      final String c = source[offset];
      if (c == ' ' || c == '\n' || c == '\r' || c == '\t' || c == ',') {
        offset++;
      } else if (c == '#') {
        while (offset < source.length && source[offset] != '\n') {
          offset++;
        }
      } else {
        return;
      }
    }
  }

  /// A description is a string before a definition, and carries nothing a
  /// client needs.
  void skipDescription() {
    _skipTrivia();
    if (offset >= source.length || source[offset] != '"') return;
    if (source.startsWith('"""', offset)) {
      final int end = source.indexOf('"""', offset + 3);
      offset = end < 0 ? source.length : end + 3;
      return;
    }
    offset++;
    while (offset < source.length && source[offset] != '"') {
      if (source[offset] == r'\') offset++;
      offset++;
    }
    if (offset < source.length) offset++;
  }

  String name() {
    _skipTrivia();
    final int start = offset;
    while (offset < source.length &&
        RegExp(r'[A-Za-z0-9_]').hasMatch(source[offset])) {
      offset++;
    }
    if (start == offset) {
      throw DVDescribedApiRefused(
        'The document does not read as SDL: expected a name at character '
        '$offset, and found "${offset < source.length ? source[offset] : 'the '
            'end of the file'}".',
      );
    }
    return source.substring(start, offset);
  }

  bool take(String token) {
    _skipTrivia();
    if (!source.startsWith(token, offset)) return false;
    offset += token.length;
    return true;
  }

  void expect(String token) {
    if (take(token)) return;
    throw DVDescribedApiRefused(
      'The document does not read as SDL: expected "$token" at character '
      '$offset.',
    );
  }

  /// A directive carries nothing a client is generated from, so it is read
  /// past rather than interpreted.
  void skipDirectives() {
    while (take('@')) {
      name();
      if (take('(')) {
        var depth = 1;
        while (depth > 0 && offset < source.length) {
          if (source[offset] == '(') depth++;
          if (source[offset] == ')') depth--;
          offset++;
        }
      }
    }
  }

  /// Everything up to the next definition, for a directive declaration.
  void skipToTopLevel() {
    while (!atEnd) {
      final int mark = offset;
      final String word = name();
      if (const <String>{
        'schema',
        'type',
        'input',
        'enum',
        'scalar',
        'interface',
        'union',
        'extend',
        'directive',
      }.contains(word)) {
        offset = mark;
        return;
      }
    }
  }

  _Type objectType() {
    final String name = this.name();
    if (take('implements')) {
      throw DVDescribedApiRefused(
        '$name implements an interface, and a client generated from a schema '
        'alone cannot select through one. Nothing was written.',
      );
    }
    skipDirectives();
    expect('{');
    final List<_Field> fields = <_Field>[];
    while (!take('}')) {
      skipDescription();
      final String field = this.name();
      final List<_Argument> arguments = <_Argument>[];
      if (take('(')) {
        while (!take(')')) {
          skipDescription();
          final String argument = this.name();
          expect(':');
          final _Ref type = ref();
          if (take('=')) defaultValue();
          skipDirectives();
          take(',');
          arguments.add(_Argument(argument, type));
        }
      }
      expect(':');
      final _Ref type = ref();
      skipDirectives();
      take(',');
      fields.add(_Field(field, type, arguments));
    }
    return _Type(name, fields);
  }

  /// A default is read past: an argument with one is optional either way,
  /// and a Dart default that disagreed with the service's would be worse
  /// than none.
  void defaultValue() {
    _skipTrivia();
    var depth = 0;
    while (offset < source.length) {
      final String c = source[offset];
      if (c == '[' || c == '{' || c == '(') depth++;
      if (c == ']' || c == '}' || c == ')') {
        if (depth == 0) return;
        depth--;
      }
      if (depth == 0 && (c == ',' || c == '\n' || c == '@')) return;
      offset++;
    }
  }

  _Ref ref() {
    _skipTrivia();
    if (take('[')) {
      final _Ref element = ref();
      expect(']');
      return _Ref(element.name, nonNull: take('!'), of: element);
    }
    final String named = name();
    return _Ref(named, nonNull: take('!'));
  }
}

const Map<String, String> _builtInScalars = <String, String>{
  'ID': 'String',
  'String': 'String',
  'Int': 'int',
  'Float': 'double',
  'Boolean': 'bool',
};

// --------------------------------------------------------------------------
// Emitting.
// --------------------------------------------------------------------------

/// One field of a generated result class, and what was selected for it.
class _Selected {
  _Selected({
    required this.name,
    required this.dartType,
    required this.nonNull,
    required this.isList,
    required this.kind,
    this.className,
  });

  final String name;
  final String dartType;
  final bool nonNull;
  final bool isList;

  /// scalar, enum or object.
  final String kind;

  /// The generated class, for an object.
  final String? className;
}

String _library({
  required String packageName,
  required String moduleId,
  required String hostName,
  required String path,
  required _Schema schema,
}) {
  final String api = '${dvClassName(moduleId)}Api';
  final String error = '${dvClassName(moduleId)}Exception';
  final StringBuffer out = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
    ..writeln('//')
    ..writeln('// Read from a GraphQL schema by dartvel add. Regenerate it')
    ..writeln('// rather than editing it: an edit here is lost on the next')
    ..writeln('// refresh (DV-MODULE-016).')
    ..writeln('library $packageName;')
    ..writeln()
    ..writeln("import 'package:dartvel_core/dartvel.dart';")
    ..writeln()
    ..write(dvDescribedApiExceptionSource(moduleId))
    ..writeln();

  // Every result class the operations need, collected while they are written
  // so the selection and the class come from one walk.
  final StringBuffer classes = StringBuffer();
  final StringBuffer methods = StringBuffer();

  for (final (String operation, String type) in <(String, String)>[
    ('query', schema.queryType),
    if (schema.mutationType != null) ('mutation', schema.mutationType!),
  ]) {
    for (final _Field field in schema.types[type]!.fields) {
      _writeOperation(
        methods: methods,
        classes: classes,
        schema: schema,
        operation: operation,
        field: field,
        error: error,
      );
    }
  }

  out
    ..writeln('/// The `$moduleId` GraphQL API.')
    ..writeln('///')
    ..writeln('/// Every call posts to the `$hostName` host declared in this')
    ..writeln("/// package's pubspec, so a base URL, a credential, a retry")
    ..writeln('/// policy and a timeout are configuration rather than code.')
    ..writeln('class $api {')
    ..writeln('  const $api();')
    ..writeln()
    ..writeln('  /// The declared host these calls go to.')
    ..writeln("  static const String host = '$hostName';")
    ..writeln()
    ..writeln('  /// The one path every call posts to.')
    ..writeln("  static const String endpoint = '$path';")
    ..writeln()
    ..write(methods)
    ..writeln('  /// Posts [document] and answers the `data` it came back')
    ..writeln('  /// with.')
    ..writeln('  ///')
    ..writeln('  /// A GraphQL service answers 200 with an `errors` array, so')
    ..writeln('  /// a call that failed looks exactly like one that worked')
    ..writeln('  /// until this is read. Errors first, then the status: a')
    ..writeln('  /// service that says what was wrong is more use than the')
    ..writeln('  /// number it said it with.')
    ..writeln('  Future<Map<String, Object?>> _post(')
    ..writeln('    String name,')
    ..writeln('    String document,')
    ..writeln('    Map<String, Object?> variables,')
    ..writeln('  ) async {')
    ..writeln('    final Response response = await const DVHttp()')
    ..writeln('        .host(host)')
    ..writeln('        .post(endpoint, json: <String, Object?>{')
    ..writeln("      'query': document,")
    ..writeln("      'variables': variables,")
    ..writeln('    });')
    ..writeln('    final Object? decoded = '
        'await response.body?.jsonDecode();')
    ..writeln('    if (decoded is! Map) {')
    ..writeln('      throw $error(name, response.status);')
    ..writeln('    }')
    ..writeln("    final Object? errors = decoded['errors'];")
    ..writeln('    if (errors is List && errors.isNotEmpty) {')
    ..writeln('      final Object? first = errors.first;')
    ..writeln('      throw $error(')
    ..writeln('        name,')
    ..writeln('        response.status,')
    ..writeln("        first is Map ? '\${first['message']}' : null,")
    ..writeln('      );')
    ..writeln('    }')
    ..writeln("    final Object? data = decoded['data'];")
    ..writeln('    if (data is! Map) {')
    ..writeln('      throw $error(name, response.status);')
    ..writeln('    }')
    ..writeln('    return data.cast<String, Object?>();')
    ..writeln('  }')
    ..writeln('}')
    ..writeln()
    ..write(classes);

  for (final MapEntry<String, List<String>> entry in schema.enums.entries) {
    out
      ..writeln()
      ..write(_enumSource(entry.key, entry.value, error));
  }
  for (final _Type input in schema.inputs.values) {
    out
      ..writeln()
      ..write(_inputSource(input, schema));
  }
  return out.toString();
}

void _writeOperation({
  required StringBuffer methods,
  required StringBuffer classes,
  required _Schema schema,
  required String operation,
  required _Field field,
  required String error,
}) {
  final String name = dvCamel(field.name);
  final String documentName = dvClassName(field.name);
  final String arguments = field.arguments
      .map((_Argument a) => a.type.nonNull
          ? 'required ${_dartType(a.type, schema)} ${dvCamel(a.name)}'
          : '${_dartType(a.type, schema)}? ${dvCamel(a.name)}')
      .join(', ');
  final String variables = field.arguments
      .map((_Argument a) => '\$${a.name}: ${a.type.sdl}')
      .join(', ');
  final String call = field.arguments
      .map((_Argument a) => '${a.name}: \$${a.name}')
      .join(', ');

  // The selection and the result class, from one walk of the graph.
  final String? className = _isLeaf(field.type, schema)
      ? null
      : '${documentName}Result';
  final String selection = className == null
      ? ''
      : ' ${_writeResultClass(
          classes: classes,
          schema: schema,
          className: className,
          typeName: field.type.name,
          path: <String>[field.type.name],
          error: error,
        )}';

  final String document = '$operation $documentName'
      '${variables.isEmpty ? '' : '($variables)'} '
      '{ ${field.name}${call.isEmpty ? '' : '($call)'}$selection }';

  final String returns = _returnType(field.type, schema, className);
  methods
    ..writeln('  /// `$operation $documentName`')
    ..writeln('  Future<$returns> $name('
        '${arguments.isEmpty ? '' : '{$arguments}'}) async {')
    ..writeln('    final Map<String, Object?> data = await _post(')
    ..writeln("      '$documentName',")
    ..writeln("      r'$document',")
    ..writeln('      <String, Object?>{');
  for (final _Argument argument in field.arguments) {
    final String value = _toWire(argument.type, dvCamel(argument.name), schema);
    methods.writeln(argument.type.nonNull
        ? "        '${argument.name}': $value,"
        : "        if (${dvCamel(argument.name)} != null) "
            "'${argument.name}': $value,");
  }
  methods
    ..writeln('      },')
    ..writeln('    );')
    ..writeln("    final Object? value = data['${field.name}'];")
    ..writeln('    return ${_readValue(field.type, schema, className, 'value')};')
    ..writeln('  }')
    ..writeln();
}

/// Writes the class for a selection of [typeName] and answers the selection
/// itself, as it goes into the document.
String _writeResultClass({
  required StringBuffer classes,
  required _Schema schema,
  required String className,
  required String typeName,
  required List<String> path,
  required String error,
}) {
  final _Type type = schema.types[typeName]!;
  final List<_Selected> selected = <_Selected>[];
  final List<String> fragments = <String>[];
  final List<String> omitted = <String>[];
  final StringBuffer nested = StringBuffer();

  for (final _Field field in type.fields) {
    // A field taking arguments is a call rather than part of a selection:
    // this cannot know what to pass, and passing nothing would ask for
    // whatever the service defaults to.
    if (field.arguments.isNotEmpty) {
      omitted.add('`${field.name}` is not selected here: it takes arguments, '
          'so it is a call rather than a field.');
      continue;
    }
    if (_isLeaf(field.type, schema)) {
      fragments.add(field.name);
      selected.add(_Selected(
        name: field.name,
        dartType: _dartType(field.type, schema),
        nonNull: field.type.nonNull,
        isList: field.type.isList,
        kind: schema.enums.containsKey(field.type.name) ? 'enum' : 'scalar',
      ));
      continue;
    }
    if (path.contains(field.type.name)) {
      omitted.add('`${field.name}` is not selected here: it returns to '
          '`${field.type.name}`, which is already on this path, and a '
          'selection cannot be infinite.');
      continue;
    }
    final String childClass = '$className${dvClassName(field.name)}';
    final String childSelection = _writeResultClass(
      classes: classes,
      schema: schema,
      className: childClass,
      typeName: field.type.name,
      path: <String>[...path, field.type.name],
      error: error,
    );
    fragments.add('${field.name} $childSelection');
    selected.add(_Selected(
      name: field.name,
      dartType: childClass,
      nonNull: field.type.nonNull,
      isList: field.type.isList,
      kind: 'object',
      className: childClass,
    ));
  }

  classes
    ..write(nested.toString())
    ..writeln('/// `$typeName`, as this call selects it.')
    ..writeln('///');
  for (final String note in omitted) {
    classes.writeln('/// $note');
  }
  if (omitted.isEmpty) {
    classes.writeln('/// Every field of the type, and each one was asked for.');
  }
  classes
    ..writeln('class $className {')
    ..writeln('  const $className({');
  for (final _Selected field in selected) {
    classes.writeln(
        '    ${field.nonNull ? 'required ' : ''}this.${dvCamel(field.name)},');
  }
  classes
    ..writeln('  });')
    ..writeln()
    ..writeln('  factory $className.fromJson(Map<String, Object?> json) =>')
    ..writeln('      $className(');
  for (final _Selected field in selected) {
    classes.writeln('        ${dvCamel(field.name)}: '
        '${_readSelected(field, "json['${field.name}']")},');
  }
  classes
    ..writeln('      );')
    ..writeln();
  for (final _Selected field in selected) {
    classes.writeln('  final ${_selectedType(field)} ${dvCamel(field.name)};');
  }
  classes.writeln('}');

  return '{ ${fragments.join(' ')} }';
}

String _selectedType(_Selected field) {
  final String inner =
      field.isList ? 'List<${field.dartType}>' : field.dartType;
  return field.nonNull ? inner : '$inner?';
}

String _readSelected(_Selected field, String access) {
  // `bang` because a value the generated code has just checked against null
  // is promoted, and a `!` on it is a warning rather than a safety net. The
  // generated file has to analyze clean or every project carrying it does
  // not.
  String one(String value, {required bool bang}) {
    final String v = bang ? '$value!' : value;
    return switch (field.kind) {
      'enum' => '${field.dartType}.fromWire($v as String)',
      'object' =>
        '${field.dartType}.fromJson(($v as Map).cast<String, Object?>())',
      _ => '$v as ${field.dartType}',
    };
  }

  if (field.isList) {
    String listOf(String value) => '<${field.dartType}>[for (final Object? '
        'entry in ($value as List)) ${one('entry', bang: true)}]';
    return field.nonNull
        ? listOf('$access!')
        : '$access == null ? null : ${listOf(access)}';
  }
  return field.nonNull
      ? one(access, bang: true)
      : '$access == null ? null : ${one(access, bang: false)}';
}

/// Whether [ref] names something a selection ends at.
bool _isLeaf(_Ref ref, _Schema schema) =>
    _builtInScalars.containsKey(ref.name) ||
    schema.scalars.contains(ref.name) ||
    schema.enums.containsKey(ref.name);

/// The Dart type for an argument or a leaf field, without its nullability.
String _dartType(_Ref ref, _Schema schema) {
  final String named = _builtInScalars[ref.name] ??
      (schema.enums.containsKey(ref.name)
          ? dvClassName(ref.name)
          : schema.inputs.containsKey(ref.name)
              ? dvClassName(ref.name)
              // A custom scalar is whatever the service says it is, and the
              // one thing every JSON encoding of one has in common is that
              // it survives as a String.
              : 'String');
  return ref.isList ? 'List<$named>' : named;
}

String _returnType(_Ref ref, _Schema schema, String? className) {
  final String named = className ?? _dartType(ref, schema);
  final String inner = ref.isList && className != null
      ? 'List<$named>'
      : className == null
          ? _dartType(ref, schema)
          : named;
  return ref.nonNull ? inner : '$inner?';
}

/// Reads one operation's answer out of `data`.
String _readValue(_Ref ref, _Schema schema, String? className, String access) {
  String one(String value, {required bool bang}) {
    final String v = bang ? '$value!' : value;
    return className != null
        ? '$className.fromJson(($v as Map).cast<String, Object?>())'
        : schema.enums.containsKey(ref.name)
            ? '${dvClassName(ref.name)}.fromWire($v as String)'
            : '$v as ${_builtInScalars[ref.name] ?? 'String'}';
  }

  if (ref.isList) {
    final String element = className ?? _dartType(ref, schema);
    String listOf(String value) => '<$element>[for (final Object? entry in '
        '($value as List)) ${one('entry', bang: true)}]';
    return ref.nonNull
        ? listOf('$access!')
        : '$access == null ? null : ${listOf(access)}';
  }
  return ref.nonNull
      ? one(access, bang: true)
      : '$access == null ? null : ${one(access, bang: false)}';
}

/// The expression that turns an argument into its JSON.
String _toWire(_Ref ref, String identifier, _Schema schema) {
  final bool isEnum = schema.enums.containsKey(ref.name);
  final bool isInput = schema.inputs.containsKey(ref.name);
  if (!isEnum && !isInput) return identifier;
  final String each = isEnum ? 'entry.wire' : 'entry.toJson()';
  if (ref.isList) {
    final String element = dvClassName(ref.name);
    return '[for (final $element entry in $identifier) $each]';
  }
  final String value = isEnum ? '.wire' : '.toJson()';
  return ref.nonNull ? '$identifier$value' : '$identifier$value';
}

String _enumSource(String name, List<String> values, String error) {
  final String className = dvClassName(name);
  final StringBuffer out = StringBuffer()
    ..writeln('/// `$name`.')
    ..writeln('enum $className {');
  for (final String value in values) {
    out.writeln("  ${dvCamel(value)}('$value'),");
  }
  out
    ..writeln('  ;')
    ..writeln()
    ..writeln('  const $className(this.wire);')
    ..writeln()
    ..writeln('  /// The spelling the service uses.')
    ..writeln('  final String wire;')
    ..writeln()
    ..writeln('  /// [wire] back to a value.')
    ..writeln('  ///')
    ..writeln('  /// A value the schema did not list throws. Reading it as')
    ..writeln('  /// null would put a wrong value into whatever the caller')
    ..writeln('  /// stores, and a service adding one is the commonest')
    ..writeln('  /// breaking change there is.')
    ..writeln('  static $className fromWire(String wire) => values.firstWhere(')
    ..writeln('        ($className value) => value.wire == wire,')
    ..writeln('        orElse: () => throw $error('
        "'$name', 200, 'unknown value \$wire'),")
    ..writeln('      );')
    ..writeln('}');
  return out.toString();
}

String _inputSource(_Type input, _Schema schema) {
  final String className = dvClassName(input.name);
  final StringBuffer out = StringBuffer()
    ..writeln('/// `${input.name}`, as the schema describes it.')
    ..writeln('class $className {')
    ..writeln('  const $className({');
  for (final _Field field in input.fields) {
    out.writeln('    ${field.type.nonNull ? 'required ' : ''}'
        'this.${dvCamel(field.name)},');
  }
  out
    ..writeln('  });')
    ..writeln();
  for (final _Field field in input.fields) {
    final String type = _dartType(field.type, schema);
    out.writeln('  final $type${field.type.nonNull ? '' : '?'} '
        '${dvCamel(field.name)};');
  }
  out
    ..writeln()
    ..writeln('  Map<String, Object?> toJson() => <String, Object?>{');
  for (final _Field field in input.fields) {
    final String value = _toWire(field.type, dvCamel(field.name), schema);
    out.writeln(field.type.nonNull
        ? "        '${field.name}': $value,"
        : "        if (${dvCamel(field.name)} != null) "
            "'${field.name}': $value,");
  }
  out
    ..writeln('      };')
    ..writeln('}');
  return out.toString();
}
