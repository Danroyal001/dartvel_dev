/// GraphQL support: a document parser, a schema registry, and an executor.
///
/// This is the executable subset a generated API needs — operations,
/// selection sets, arguments, variables, aliases, fragments, and
/// introspection. It is not a general GraphQL server library: directives and
/// subscriptions are not implemented, and asking for them is an error rather
/// than a silent no-op.
library dartvel_core.graphql;

import 'dart:async';

/// A resolvable field on a registered type.
class DVGraphQLField {
  final String name;

  /// The SDL type, e.g. `String!`, `[User!]!`.
  final String type;

  /// Argument names to SDL types.
  final Map<String, String> args;

  /// Resolves the field. [parent] is the enclosing object's resolved value
  /// (null at the root); absent, the field reads `parent[name]`.
  final FutureOr<Object?> Function(
    Map<String, Object?> args,
    Object? parent,
  )? resolve;

  const DVGraphQLField(
    this.name,
    this.type, {
    this.args = const <String, String>{},
    this.resolve,
  });
}

/// A registered object type.
class DVGraphQLObjectType {
  final String name;
  final Map<String, DVGraphQLField> fields;

  DVGraphQLObjectType(this.name, Iterable<DVGraphQLField> fields)
      : fields = <String, DVGraphQLField>{
          for (final field in fields) field.name: field,
        };
}

/// The schema registry and executor.
class DVGraphQL {
  DVGraphQL._();

  static final Map<String, DVGraphQLObjectType> _types = {};
  static final Map<String, DVGraphQLField> _queries = {};
  static final Map<String, DVGraphQLField> _mutations = {};
  static final Map<String, DVGraphQLField> _subscriptions = {};

  static void registerType(DVGraphQLObjectType type) {
    _types[type.name] = type;
  }

  static void registerQuery(DVGraphQLField field) {
    _queries[field.name] = field;
  }

  static void registerMutation(DVGraphQLField field) {
    _mutations[field.name] = field;
  }

  /// Registers a subscription. Its resolver returns a [Stream]; each event
  /// becomes one `{data}` payload shaped by the client's selection set.
  static void registerSubscription(DVGraphQLField field) {
    _subscriptions[field.name] = field;
  }

  /// Drops every registration. Intended for tests.
  static void reset() {
    _types.clear();
    _queries.clear();
    _mutations.clear();
    _subscriptions.clear();
  }

  /// The schema as SDL, for humans and for tooling that prefers it to an
  /// introspection round trip.
  static String toSdl() {
    final buffer = StringBuffer();
    String fieldLine(DVGraphQLField field) {
      final args = field.args.isEmpty
          ? ''
          : '(${field.args.entries.map((e) => '${e.key}: ${e.value}').join(', ')})';
      return '  ${field.name}$args: ${field.type}';
    }

    if (_queries.isNotEmpty) {
      buffer.writeln('type Query {');
      for (final field in _queries.values) {
        buffer.writeln(fieldLine(field));
      }
      buffer.writeln('}');
    }
    if (_mutations.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.writeln('type Mutation {');
      for (final field in _mutations.values) {
        buffer.writeln(fieldLine(field));
      }
      buffer.writeln('}');
    }
    if (_subscriptions.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.writeln('type Subscription {');
      for (final field in _subscriptions.values) {
        buffer.writeln(fieldLine(field));
      }
      buffer.writeln('}');
    }
    for (final type in _types.values) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.writeln('type ${type.name} {');
      for (final field in type.fields.values) {
        buffer.writeln(fieldLine(field));
      }
      buffer.writeln('}');
    }
    return buffer.toString();
  }

  /// Executes [document], returning the spec-shaped `{data}` or `{errors}`.
  ///
  /// A request-level failure (parse error, unknown operation) yields only
  /// `errors`; a field-level failure nulls that field and appends an error,
  /// as the GraphQL spec requires — one bad resolver does not take down the
  /// whole response.
  static Future<Map<String, Object?>> execute(
    String document, {
    Map<String, Object?>? variables,
    String? operationName,
  }) async {
    _ParsedDocument parsed;
    try {
      parsed = _Parser(document).parseDocument();
    } on FormatException catch (error) {
      return <String, Object?>{
        'errors': <Object?>[
          <String, Object?>{'message': error.message},
        ],
      };
    }

    final operation = parsed.operation(operationName);
    if (operation == null) {
      return <String, Object?>{
        'errors': <Object?>[
          <String, Object?>{
            'message': operationName == null
                ? 'The document declares multiple operations; pass '
                    'operationName to choose one.'
                : 'No operation named "$operationName" in the document.',
          },
        ],
      };
    }

    final roots = switch (operation.kind) {
      'query' => _queries,
      'mutation' => _mutations,
      _ => null,
    };
    if (roots == null) {
      return <String, Object?>{
        'errors': <Object?>[
          <String, Object?>{
            'message': 'A ${operation.kind} operation yields a stream of '
                'results; use DVGraphQL.subscribe instead of execute.',
          },
        ],
      };
    }

    final errors = <Map<String, Object?>>[];
    final context = _ExecutionContext(
      variables: variables ?? const <String, Object?>{},
      fragments: parsed.fragments,
      errors: errors,
    );
    final data = <String, Object?>{};
    for (final selection
        in context.expand(operation.selections)) {
      // Introspection resolves from the registry rather than a resolver, so
      // tooling works against whatever the application registered.
      if (selection.name == '__schema') {
        data[selection.alias] = context.project(
          introspectionSchema(),
          selection,
        );
        continue;
      }
      if (selection.name == '__type') {
        final name = context.argument(selection, 'name');
        final types =
            introspectionSchema()['types']! as List<Object?>;
        Map<String, Object?>? match;
        for (final type in types) {
          if ((type! as Map)['name'] == name) {
            match = (type as Map).cast<String, Object?>();
            break;
          }
        }
        data[selection.alias] =
            match == null ? null : context.project(match, selection);
        continue;
      }
      if (selection.name == '__typename') {
        data[selection.alias] =
            operation.kind == 'mutation' ? 'Mutation' : 'Query';
        continue;
      }

      final field = roots[selection.name];
      if (field == null) {
        errors.add(<String, Object?>{
          'message':
              'Unknown ${operation.kind} field "${selection.name}".',
        });
        data[selection.alias] = null;
        continue;
      }
      data[selection.alias] =
          await context.resolveField(field, selection, null);
    }
    return <String, Object?>{
      'data': data,
      if (errors.isNotEmpty) 'errors': errors,
    };
  }

  /// Runs a subscription, yielding one spec-shaped result per event.
  ///
  /// The resolver returns a Stream; each event is completed against the
  /// client's selection set, so a subscriber receives exactly the fields it
  /// asked for rather than the raw payload.
  static Stream<Map<String, Object?>> subscribe(
    String document, {
    Map<String, Object?>? variables,
    String? operationName,
  }) {
    _ParsedDocument parsed;
    try {
      parsed = _Parser(document).parseDocument();
    } on FormatException catch (error) {
      return Stream<Map<String, Object?>>.value(<String, Object?>{
        'errors': <Object?>[
          <String, Object?>{'message': error.message},
        ],
      });
    }

    final operation = parsed.operation(operationName);
    if (operation == null || operation.kind != 'subscription') {
      return Stream<Map<String, Object?>>.value(<String, Object?>{
        'errors': <Object?>[
          <String, Object?>{
            'message': operation == null
                ? 'No subscription operation to run.'
                : 'That operation is a ${operation.kind}; use execute.',
          },
        ],
      });
    }

    // One root field per subscription: the spec requires it, and a client
    // subscribing to two streams at once has no defined event ordering.
    final selections = <_Selection>[];
    final context = _ExecutionContext(
      variables: variables ?? const <String, Object?>{},
      fragments: parsed.fragments,
      errors: <Map<String, Object?>>[],
    );
    try {
      selections.addAll(context.expand(operation.selections));
    } on FormatException catch (error) {
      return Stream<Map<String, Object?>>.value(<String, Object?>{
        'errors': <Object?>[
          <String, Object?>{'message': error.message},
        ],
      });
    }
    if (selections.length != 1) {
      return Stream<Map<String, Object?>>.value(<String, Object?>{
        'errors': <Object?>[
          <String, Object?>{
            'message': 'A subscription must select exactly one root field; '
                'this one selects ${selections.length}.',
          },
        ],
      });
    }

    final selection = selections.single;
    final field = _subscriptions[selection.name];
    if (field == null) {
      return Stream<Map<String, Object?>>.value(<String, Object?>{
        'errors': <Object?>[
          <String, Object?>{
            'message': 'Unknown subscription field "${selection.name}".',
          },
        ],
      });
    }

    final resolve = field.resolve;
    if (resolve == null) {
      return Stream<Map<String, Object?>>.value(<String, Object?>{
        'errors': <Object?>[
          <String, Object?>{
            'message': 'Subscription "${field.name}" has no resolver.',
          },
        ],
      });
    }

    late StreamController<Map<String, Object?>> controller;
    StreamSubscription<Object?>? source;

    Future<void> start() async {
      Object? stream;
      try {
        final args = <String, Object?>{
          for (final entry in selection.arguments.entries)
            entry.key: context.argument(selection, entry.key),
        };
        stream = await resolve(args, null);
      } catch (error) {
        controller.add(<String, Object?>{
          'errors': <Object?>[
            <String, Object?>{'message': '$error'},
          ],
        });
        await controller.close();
        return;
      }
      if (stream is! Stream) {
        controller.add(<String, Object?>{
          'errors': <Object?>[
            <String, Object?>{
              'message': 'Subscription "${field.name}" must resolve to a '
                  'Stream; it returned ${stream.runtimeType}.',
            },
          ],
        });
        await controller.close();
        return;
      }

      source = stream.listen(
        (Object? event) async {
          // Each event carries its own errors, so one bad payload does not
          // end a long-lived subscription.
          final errors = <Map<String, Object?>>[];
          final eventContext = _ExecutionContext(
            variables: variables ?? const <String, Object?>{},
            fragments: parsed.fragments,
            errors: errors,
          );
          final value = await eventContext._complete(
            event,
            field.type,
            selection,
          );
          controller.add(<String, Object?>{
            'data': <String, Object?>{selection.alias: value},
            if (errors.isNotEmpty) 'errors': errors,
          });
        },
        onError: (Object error) => controller.add(<String, Object?>{
          'errors': <Object?>[
            <String, Object?>{'message': '$error'},
          ],
        }),
        onDone: () => unawaited(controller.close()),
      );
    }

    controller = StreamController<Map<String, Object?>>(
      onListen: () => unawaited(start()),
      // Cancelling the subscriber must cancel the source, or a closed client
      // leaves the producer running forever.
      onCancel: () async => source?.cancel(),
    );
    return controller.stream;
  }

  static DVGraphQLObjectType? typeNamed(String name) => _types[_bare(name)];

  /// The introspection document, in the shape GraphQL clients expect.
  ///
  /// Built from the same registry that serves queries, so it cannot drift
  /// from what actually executes — the failure mode a hand-maintained schema
  /// document has.
  static Map<String, Object?> introspectionSchema() {
    final objectTypes = <Map<String, Object?>>[
      if (_queries.isNotEmpty) _introspectFields('Query', _queries),
      if (_mutations.isNotEmpty) _introspectFields('Mutation', _mutations),
      if (_subscriptions.isNotEmpty)
        _introspectFields('Subscription', _subscriptions),
      for (final type in _types.values)
        _introspectFields(type.name, type.fields),
    ];
    final scalars = <String>{
      for (final type in _types.values)
        for (final field in type.fields.values) _bare(field.type),
      for (final field in _queries.values) _bare(field.type),
      for (final field in _mutations.values) _bare(field.type),
      for (final field in _subscriptions.values) _bare(field.type),
      for (final field in <DVGraphQLField>[
        ..._queries.values,
        ..._mutations.values,
        ..._subscriptions.values,
        for (final type in _types.values) ...type.fields.values,
      ])
        for (final argument in field.args.values) _bare(argument),
    }.where((String name) => !_types.containsKey(name)).toList()
      ..sort();

    return <String, Object?>{
      'queryType':
          _queries.isEmpty ? null : <String, Object?>{'name': 'Query'},
      'mutationType':
          _mutations.isEmpty ? null : <String, Object?>{'name': 'Mutation'},
      'subscriptionType': _subscriptions.isEmpty
          ? null
          : <String, Object?>{'name': 'Subscription'},
      'directives': <Object?>[],
      'types': <Object?>[
        ...objectTypes,
        for (final scalar in scalars)
          <String, Object?>{
            'kind': 'SCALAR',
            'name': scalar,
            'fields': null,
            'inputFields': null,
            'interfaces': null,
            'enumValues': null,
            'possibleTypes': null,
          },
      ],
    };
  }

  static Map<String, Object?> _introspectFields(
    String name,
    Map<String, DVGraphQLField> fields,
  ) =>
      <String, Object?>{
        'kind': 'OBJECT',
        'name': name,
        'interfaces': <Object?>[],
        'inputFields': null,
        'enumValues': null,
        'possibleTypes': null,
        'fields': <Object?>[
          for (final field in fields.values)
            <String, Object?>{
              'name': field.name,
              'description': null,
              'isDeprecated': false,
              'deprecationReason': null,
              'type': typeReference(field.type),
              'args': <Object?>[
                for (final argument in field.args.entries)
                  <String, Object?>{
                    'name': argument.key,
                    'description': null,
                    'defaultValue': null,
                    'type': typeReference(argument.value),
                  },
              ],
            },
        ],
      };

  /// An SDL type string as an introspection type reference.
  ///
  /// `[User!]!` becomes NON_NULL(LIST(NON_NULL(OBJECT User))) — the nesting
  /// clients rely on to know what can be null.
  static Map<String, Object?> typeReference(String type) {
    final trimmed = type.trim();
    if (trimmed.endsWith('!')) {
      return <String, Object?>{
        'kind': 'NON_NULL',
        'name': null,
        'ofType': typeReference(trimmed.substring(0, trimmed.length - 1)),
      };
    }
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      return <String, Object?>{
        'kind': 'LIST',
        'name': null,
        'ofType': typeReference(trimmed.substring(1, trimmed.length - 1)),
      };
    }
    return <String, Object?>{
      'kind': _types.containsKey(trimmed) ? 'OBJECT' : 'SCALAR',
      'name': trimmed,
      'ofType': null,
    };
  }

  /// `[User!]!` → `User`.
  static String _bare(String type) =>
      type.replaceAll(RegExp(r'[\[\]!]'), '');
}

class _ExecutionContext {
  final Map<String, Object?> variables;
  final Map<String, List<_Selection>> fragments;
  final List<Map<String, Object?>> errors;

  _ExecutionContext({
    required this.variables,
    required this.fragments,
    required this.errors,
  });

  /// Expands fragment spreads into plain field selections.
  Iterable<_Selection> expand(List<_Selection> selections) sync* {
    for (final selection in selections) {
      if (selection.fragmentName != null) {
        final fragment = fragments[selection.fragmentName];
        if (fragment == null) {
          throw FormatException(
            'Unknown fragment "${selection.fragmentName}".',
          );
        }
        yield* expand(fragment);
      } else {
        yield selection;
      }
    }
  }

  Future<Object?> resolveField(
    DVGraphQLField field,
    _Selection selection,
    Object? parent,
  ) async {
    Object? value;
    try {
      final args = <String, Object?>{
        for (final entry in selection.arguments.entries)
          entry.key: _coerce(entry.value),
      };
      final resolve = field.resolve;
      value = resolve != null
          ? await resolve(args, parent)
          : (parent is Map ? parent[field.name] : null);
    } catch (error) {
      // Field errors null the field and are reported; they do not take the
      // response down.
      errors.add(<String, Object?>{
        'message': '$error',
        'path': <Object?>[selection.alias],
      });
      return null;
    }
    return _complete(value, field.type, selection);
  }

  Future<Object?> _complete(
    Object? value,
    String type,
    _Selection selection,
  ) async {
    if (value == null) return null;
    if (value is List) {
      return <Object?>[
        for (final item in value) await _complete(item, type, selection),
      ];
    }
    final objectType = DVGraphQL.typeNamed(type);
    if (objectType == null || selection.selections.isEmpty) return value;

    final result = <String, Object?>{};
    for (final sub in expand(selection.selections)) {
      if (sub.name == '__typename') {
        result[sub.alias] = objectType.name;
        continue;
      }
      final subField = objectType.fields[sub.name];
      if (subField == null) {
        errors.add(<String, Object?>{
          'message':
              'Unknown field "${sub.name}" on type ${objectType.name}.',
        });
        result[sub.alias] = null;
        continue;
      }
      result[sub.alias] = await resolveField(subField, sub, value);
    }
    return result;
  }

  /// Applies a selection set to a plain map — how introspection results are
  /// shaped, since they are data rather than registered types.
  Object? project(Object? value, _Selection selection) {
    if (value == null) return null;
    if (value is List) {
      return <Object?>[for (final item in value) project(item, selection)];
    }
    if (selection.selections.isEmpty || value is! Map) return value;

    final result = <String, Object?>{};
    for (final sub in expand(selection.selections)) {
      result[sub.alias] = project(value[sub.name], sub);
    }
    return result;
  }

  /// One resolved argument of [selection].
  Object? argument(_Selection selection, String name) =>
      _coerce(selection.arguments[name]);

  Object? _coerce(Object? literal) {
    if (literal is _Variable) {
      if (!variables.containsKey(literal.name)) {
        throw FormatException('Variable "\$${literal.name}" was not provided.');
      }
      return variables[literal.name];
    }
    if (literal is List) return literal.map(_coerce).toList();
    if (literal is Map) {
      return literal.map((Object? k, Object? v) => MapEntry(k, _coerce(v)));
    }
    return literal;
  }
}

// --- document model ---------------------------------------------------------

class _ParsedDocument {
  final List<_Operation> operations;
  final Map<String, List<_Selection>> fragments;

  _ParsedDocument(this.operations, this.fragments);

  _Operation? operation(String? name) {
    if (name != null) {
      for (final op in operations) {
        if (op.name == name) return op;
      }
      return null;
    }
    return operations.length == 1 ? operations.single : null;
  }
}

class _Operation {
  final String kind;
  final String? name;
  final List<_Selection> selections;

  _Operation(this.kind, this.name, this.selections);
}

class _Selection {
  final String name;
  final String alias;
  final Map<String, Object?> arguments;
  final List<_Selection> selections;

  /// Set instead of [name] for a fragment spread.
  final String? fragmentName;

  _Selection({
    this.name = '',
    String? alias,
    this.arguments = const <String, Object?>{},
    this.selections = const <_Selection>[],
    this.fragmentName,
  }) : alias = alias ?? name;
}

class _Variable {
  final String name;

  const _Variable(this.name);
}

// --- parser -----------------------------------------------------------------

class _Parser {
  final String source;
  int _pos = 0;

  _Parser(this.source);

  _ParsedDocument parseDocument() {
    final operations = <_Operation>[];
    final fragments = <String, List<_Selection>>{};
    _skipIgnored();
    while (_pos < source.length) {
      if (_peekWord('fragment')) {
        _readWord();
        final name = _readName();
        _expectWord('on');
        _readName(); // The type condition is not enforced.
        fragments[name] = _parseSelectionSet();
      } else if (_peekWord('query') ||
          _peekWord('mutation') ||
          _peekWord('subscription')) {
        final kind = _readWord();
        String? name;
        _skipIgnored();
        if (_pos < source.length && _isNameStart(source[_pos])) {
          name = _readName();
        }
        _skipIgnored();
        if (_pos < source.length && source[_pos] == '(') {
          _skipVariableDefinitions();
        }
        operations.add(_Operation(kind, name, _parseSelectionSet()));
      } else if (_pos < source.length && source[_pos] == '{') {
        // Query shorthand.
        operations.add(_Operation('query', null, _parseSelectionSet()));
      } else {
        throw FormatException(
          'Unexpected input at offset $_pos: '
          '"${source.substring(_pos, _pos + 20 > source.length ? source.length : _pos + 20)}"',
        );
      }
      _skipIgnored();
    }
    if (operations.isEmpty) {
      throw const FormatException('The document contains no operations.');
    }
    return _ParsedDocument(operations, fragments);
  }

  List<_Selection> _parseSelectionSet() {
    _expect('{');
    final selections = <_Selection>[];
    _skipIgnored();
    while (_pos < source.length && source[_pos] != '}') {
      if (source.startsWith('...', _pos)) {
        _pos += 3;
        _skipIgnored();
        if (_peekWord('on')) {
          // Inline fragment: the type condition is not enforced, its
          // selections apply directly.
          _readWord();
          _readName();
          selections.addAll(_parseSelectionSet());
        } else {
          selections.add(_Selection(fragmentName: _readName()));
        }
        _skipIgnored();
        continue;
      }

      var name = _readName();
      String? alias;
      _skipIgnored();
      if (_pos < source.length && source[_pos] == ':') {
        _pos++;
        alias = name;
        name = _readName();
        _skipIgnored();
      }
      var arguments = const <String, Object?>{};
      if (_pos < source.length && source[_pos] == '(') {
        arguments = _parseArguments();
        _skipIgnored();
      }
      var subSelections = const <_Selection>[];
      if (_pos < source.length && source[_pos] == '{') {
        subSelections = _parseSelectionSet();
        _skipIgnored();
      }
      selections.add(_Selection(
        name: name,
        alias: alias,
        arguments: arguments,
        selections: subSelections,
      ));
    }
    _expect('}');
    _skipIgnored();
    return selections;
  }

  Map<String, Object?> _parseArguments() {
    _expect('(');
    final arguments = <String, Object?>{};
    _skipIgnored();
    while (_pos < source.length && source[_pos] != ')') {
      final name = _readName();
      _expect(':');
      arguments[name] = _parseValue();
      _skipIgnored();
    }
    _expect(')');
    return arguments;
  }

  Object? _parseValue() {
    _skipIgnored();
    final char = source[_pos];
    if (char == r'$') {
      _pos++;
      return _Variable(_readName());
    }
    if (char == '"') return _readString();
    if (char == '[') {
      _pos++;
      final values = <Object?>[];
      _skipIgnored();
      while (source[_pos] != ']') {
        values.add(_parseValue());
        _skipIgnored();
      }
      _pos++;
      return values;
    }
    if (char == '{') {
      _pos++;
      final object = <String, Object?>{};
      _skipIgnored();
      while (source[_pos] != '}') {
        final name = _readName();
        _expect(':');
        object[name] = _parseValue();
        _skipIgnored();
      }
      _pos++;
      return object;
    }
    final word = _readRawValue();
    if (word == 'true') return true;
    if (word == 'false') return false;
    if (word == 'null') return null;
    final asInt = int.tryParse(word);
    if (asInt != null) return asInt;
    final asDouble = double.tryParse(word);
    if (asDouble != null) return asDouble;
    return word; // Enum value: carried as its name.
  }

  void _skipVariableDefinitions() {
    // Variable definitions are declarative; values arrive separately, so the
    // definitions are skipped structurally.
    var depth = 0;
    do {
      if (source[_pos] == '(') depth++;
      if (source[_pos] == ')') depth--;
      _pos++;
    } while (depth > 0 && _pos < source.length);
    _skipIgnored();
  }

  String _readString() {
    _expect('"');
    final buffer = StringBuffer();
    while (source[_pos] != '"') {
      if (source[_pos] == r'\') {
        _pos++;
        buffer.write(switch (source[_pos]) {
          'n' => '\n',
          't' => '\t',
          'r' => '\r',
          final other => other,
        });
      } else {
        buffer.write(source[_pos]);
      }
      _pos++;
    }
    _pos++;
    return buffer.toString();
  }

  String _readName() {
    _skipIgnored();
    final start = _pos;
    while (_pos < source.length && _isNameChar(source[_pos])) {
      _pos++;
    }
    if (start == _pos) {
      throw FormatException('Expected a name at offset $_pos.');
    }
    return source.substring(start, _pos);
  }

  String _readRawValue() {
    final start = _pos;
    while (_pos < source.length &&
        RegExp(r'[A-Za-z0-9_.+-]').hasMatch(source[_pos])) {
      _pos++;
    }
    if (start == _pos) {
      throw FormatException('Expected a value at offset $_pos.');
    }
    return source.substring(start, _pos);
  }

  String _readWord() => _readName();

  bool _peekWord(String word) {
    _skipIgnored();
    return source.startsWith(word, _pos) &&
        (_pos + word.length == source.length ||
            !_isNameChar(source[_pos + word.length]));
  }

  void _expectWord(String word) {
    if (!_peekWord(word)) {
      throw FormatException('Expected "$word" at offset $_pos.');
    }
    _readWord();
  }

  void _expect(String char) {
    _skipIgnored();
    if (_pos >= source.length || source[_pos] != char) {
      throw FormatException('Expected "$char" at offset $_pos.');
    }
    _pos++;
  }

  void _skipIgnored() {
    while (_pos < source.length) {
      final char = source[_pos];
      if (char == '#') {
        while (_pos < source.length && source[_pos] != '\n') {
          _pos++;
        }
      } else if (char == ' ' ||
          char == '\t' ||
          char == '\n' ||
          char == '\r' ||
          char == ',') {
        _pos++;
      } else {
        return;
      }
    }
  }

  static bool _isNameStart(String char) =>
      RegExp(r'[A-Za-z_]').hasMatch(char);

  static bool _isNameChar(String char) =>
      RegExp(r'[A-Za-z0-9_]').hasMatch(char);
}
