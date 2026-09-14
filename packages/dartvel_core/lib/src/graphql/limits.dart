part of 'graphql.dart';

/// Who a GraphQL endpoint answers introspection for.
enum DVGraphQLIntrospection {
  /// Only a build that is not a production build. The default: introspection
  /// is the fastest way to learn a schema, and a generated schema is the whole
  /// data model.
  development,

  /// Nobody.
  never,

  /// Only a request the caller has authenticated.
  authenticated,
}

/// The budget every GraphQL operation is checked against before any resolver
/// runs (`dartvel.api.graphql` in `pubspec.yaml`).
///
/// A budget left null is `auto`: derived from the registered schema rather
/// than guessed, so it moves when the model graph does. See
/// [DVGraphQL.autoMaxDepth] and [DVGraphQL.autoMaxCost] for what each derives.
class DVGraphQLLimits {
  const DVGraphQLLimits({
    this.maxDepth,
    this.maxCost,
    this.defaultPageSize = 50,
    this.introspection = DVGraphQLIntrospection.development,
    this.production = const bool.fromEnvironment('dart.vm.product'),
  });

  /// The deepest selection an operation may make, or null for auto.
  final int? maxDepth;

  /// The most an operation may cost, or null for auto.
  final int? maxCost;

  /// What a list field is priced at when the query passes no page size and
  /// the field declares none.
  final int defaultPageSize;

  final DVGraphQLIntrospection introspection;

  /// Whether this is a production build, which is what
  /// [DVGraphQLIntrospection.development] refuses. Defaults to whether the
  /// process is AOT-compiled, which is how a deployed backend runs.
  final bool production;
}

/// The depth and cost of one operation, as the budget sees them.
class DVGraphQLQueryCost {
  const DVGraphQLQueryCost({required this.depth, required this.cost});

  /// Nesting levels, counting the root fields as one and a scalar as a level.
  final int depth;

  /// Each field costs what it declares (at least 1) plus its selections, and
  /// a list field multiplies that by its page size.
  final int cost;
}

/// An operation refused for exceeding its depth or cost budget
/// (`DV-EDGE-001`).
///
/// It is refused whole. A partial answer would be worse: a client cannot tell
/// a trimmed response from a real one, and neither can a cache.
class DVGraphQLRefusal implements Exception {
  const DVGraphQLRefusal({
    required this.budget,
    required this.limit,
    required this.actual,
  });

  /// `depth` or `cost`.
  final String budget;
  final int limit;
  final int actual;

  String get code => 'DV-EDGE-001';

  int get excess => actual - limit;

  String get message => 'Refused: this query\'s $budget is $actual, over the '
      '$budget budget of $limit by $excess. Nothing was resolved; ask for '
      'less rather than expecting part of it.';

  Map<String, Object?> toResponse() => <String, Object?>{
        'errors': <Object?>[
          <String, Object?>{
            'message': message,
            'extensions': <String, Object?>{
              'code': code,
              'budget': budget,
              'limit': limit,
              'actual': actual,
              'excess': excess,
            },
          },
        ],
      };

  @override
  String toString() => 'DVGraphQLRefusal($code): $message';
}

/// Whether an endpoint answers only documents it has seen before.
enum DVPersistedQueryMode {
  /// Any document runs; a hash is looked up when it is sent alone.
  off,

  /// Any document runs, but a hash must be the hash of the document sent
  /// with it.
  prefer,

  /// Only documents in the manifest run (`DV-EDGE-002`).
  require,
}

/// The persisted-query manifest: every document the application's own
/// clients can send, keyed by the sha256 of its exact text.
class DVPersistedQueries {
  DVPersistedQueries({
    this.mode = DVPersistedQueryMode.off,
    Iterable<String> documents = const <String>[],
  }) : _documents = <String, String>{
          for (final document in documents) hashOf(document): document,
        };

  /// A manifest as the build ships it, hash to document.
  ///
  /// Every hash is checked against its document: a manifest entry whose hash
  /// is not its document's lets that document run under a hash the endpoint
  /// trusts.
  DVPersistedQueries.fromManifest(
    Map<String, String> manifest, {
    this.mode = DVPersistedQueryMode.off,
  }) : _documents = <String, String>{} {
    for (final entry in manifest.entries) {
      final hash = hashOf(entry.value);
      if (hash != entry.key.toLowerCase()) {
        throw ArgumentError.value(
          entry.key,
          'manifest',
          'is not the sha256 of the document it names',
        );
      }
      _documents[hash] = entry.value;
    }
  }

  final DVPersistedQueryMode mode;
  final Map<String, String> _documents;

  /// The lowercase hex sha256 of [document]'s UTF-8 bytes.
  static String hashOf(String document) =>
      sha256.convert(utf8.encode(document)).toString();

  /// The document persisted under [hash], or null.
  String? documentFor(String hash) => _documents[hash.toLowerCase()];

  Iterable<String> get hashes => _documents.keys;
}

// --- enforcement --------------------------------------------------------------

/// Where saturating cost arithmetic stops. Below 2^53, so it is exact on the
/// web too, and far above any budget worth configuring.
const int _costCeiling = 1 << 50;

int _addCost(int a, int b) {
  final sum = a + b;
  return sum > _costCeiling ? _costCeiling : sum;
}

int _multiplyCost(int a, int b) {
  if (a == 0 || b == 0) return 0;
  if (a > _costCeiling ~/ b) return _costCeiling;
  return a * b;
}

/// Arguments a list field is conventionally paged by.
const List<String> _pageSizeArguments = <String>[
  'first',
  'last',
  'limit',
  'pageSize',
  'perPage',
  'take',
];

Map<String, DVGraphQLField> _rootFieldsOf(String kind) => switch (kind) {
      'mutation' => DVGraphQL._mutations,
      'subscription' => DVGraphQL._subscriptions,
      _ => DVGraphQL._queries,
    };

int _ownCost(DVGraphQLField field) {
  final declared = field.cost ?? 1;
  // No field is free to ask for; a zero would let a document repeat it
  // without limit.
  return declared < 1 ? 1 : declared;
}

bool _isList(DVGraphQLField field) => field.type.contains('[');

/// Prices an operation without expanding it.
///
/// Every selection set is priced once per type it is selected on and the
/// result reused, so a chain of fragments that doubles at every level costs
/// the analyser one pass per fragment rather than two to the power of the
/// chain.
class _CostAnalyzer {
  _CostAnalyzer(this.context, this.limits);

  final _ExecutionContext context;
  final DVGraphQLLimits limits;
  final Map<List<_Selection>, Map<String, DVGraphQLQueryCost>> _priced =
      Map<List<_Selection>, Map<String, DVGraphQLQueryCost>>.identity();
  final Set<String> _spreading = <String>{};

  DVGraphQLQueryCost operation(_Operation operation) => _selectionSet(
        operation.selections,
        _rootFieldsOf(operation.kind),
        operation.kind,
      );

  DVGraphQLQueryCost _selectionSet(
    List<_Selection> selections,
    Map<String, DVGraphQLField> fields,
    String typeName,
  ) {
    final priced = _priced[selections]?[typeName];
    if (priced != null) return priced;

    var depth = 0;
    var cost = 0;
    for (final selection in selections) {
      if (!context._included(selection.directives)) continue;

      final DVGraphQLQueryCost part;
      final fragmentName = selection.fragmentName;
      if (fragmentName != null) {
        final fragment = context.fragments[fragmentName];
        if (fragment == null) {
          throw FormatException('Unknown fragment "$fragmentName".');
        }
        if (!_spreading.add(fragmentName)) {
          throw FormatException(
            'Fragment "$fragmentName" spreads itself through a cycle of '
            'fragment spreads.',
          );
        }
        try {
          part = _selectionSet(fragment, fields, typeName);
        } finally {
          _spreading.remove(fragmentName);
        }
      } else if (selection.isInlineFragment) {
        part = _selectionSet(selection.selections, fields, typeName);
      } else {
        part = _field(selection, fields);
      }
      if (part.depth > depth) depth = part.depth;
      cost = _addCost(cost, part.cost);
    }

    final result = DVGraphQLQueryCost(depth: depth, cost: cost);
    (_priced[selections] ??= <String, DVGraphQLQueryCost>{})[typeName] =
        result;
    return result;
  }

  DVGraphQLQueryCost _field(
    _Selection selection,
    Map<String, DVGraphQLField> fields,
  ) {
    // Introspection answers from the registry, not a resolver, and is
    // governed by its own policy.
    if (selection.name.startsWith('__')) {
      return const DVGraphQLQueryCost(depth: 1, cost: 0);
    }

    final field = fields[selection.name];
    final target = field == null ? null : DVGraphQL.typeNamed(field.type);
    var children = const DVGraphQLQueryCost(depth: 0, cost: 0);
    if (selection.selections.isNotEmpty) {
      // An unknown field still has its selections priced: the executor
      // reports it, but its siblings resolve.
      children = _selectionSet(
        selection.selections,
        target?.fields ?? const <String, DVGraphQLField>{},
        target?.name ?? '',
      );
    }
    final own = field == null ? 1 : _ownCost(field);
    final multiplier =
        field != null && _isList(field) ? _pageSize(selection, field) : 1;
    return DVGraphQLQueryCost(
      depth: 1 + children.depth,
      cost: _multiplyCost(multiplier, _addCost(own, children.cost)),
    );
  }

  int _pageSize(_Selection selection, DVGraphQLField field) {
    for (final name in _pageSizeArguments) {
      if (!selection.arguments.containsKey(name)) continue;
      Object? value;
      try {
        value = context._coerce(selection.arguments[name]);
      } on FormatException {
        continue;
      }
      if (value is num && value > 0) {
        return value >= _costCeiling ? _costCeiling : value.ceil();
      }
    }
    return field.pageSize ?? limits.defaultPageSize;
  }
}

/// The deepest an operation can go without walking a cycle twice.
///
/// Types are grouped into strongly connected components, so a cycle is one
/// node and the longest route through the schema is a longest path in a DAG
/// -- linear, where enumerating simple paths is exponential. A component
/// contributes one level per type in it, plus one step back in when it is a
/// cycle, so `users { friends { name } }` fits and a walk around the cycle
/// does not. A scalar at the end is one more level.
int _computeAutoMaxDepth() {
  final types = DVGraphQL._types;

  Iterable<String> successors(String name) sync* {
    for (final field in types[name]!.fields.values) {
      final target = DVGraphQL.typeNamed(field.type);
      if (target != null && types.containsKey(target.name)) {
        yield target.name;
      }
    }
  }

  // Tarjan's algorithm.
  final index = <String, int>{};
  final low = <String, int>{};
  final onStack = <String>{};
  final stack = <String>[];
  final componentOf = <String, int>{};
  final components = <List<String>>[];
  var counter = 0;

  void connect(String type) {
    index[type] = counter;
    low[type] = counter;
    counter++;
    stack.add(type);
    onStack.add(type);
    for (final next in successors(type)) {
      if (!index.containsKey(next)) {
        connect(next);
        if (low[next]! < low[type]!) low[type] = low[next]!;
      } else if (onStack.contains(next) && index[next]! < low[type]!) {
        low[type] = index[next]!;
      }
    }
    if (low[type] == index[type]) {
      final members = <String>[];
      String member;
      do {
        member = stack.removeLast();
        onStack.remove(member);
        componentOf[member] = components.length;
        members.add(member);
      } while (member != type);
      components.add(members);
    }
  }

  for (final type in types.keys) {
    if (!index.containsKey(type)) connect(type);
  }

  final levels = <int, int>{};
  int levelOf(int component) {
    final known = levels[component];
    if (known != null) return known;
    final members = components[component];
    var cyclic = members.length > 1;
    var deepest = 0;
    for (final member in members) {
      for (final next in successors(member)) {
        final nextComponent = componentOf[next]!;
        if (nextComponent == component) {
          cyclic = true;
          continue;
        }
        final level = levelOf(nextComponent);
        if (level > deepest) deepest = level;
      }
    }
    return levels[component] = members.length + (cyclic ? 1 : 0) + deepest;
  }

  var depth = 1;
  for (final roots in <Map<String, DVGraphQLField>>[
    DVGraphQL._queries,
    DVGraphQL._mutations,
    DVGraphQL._subscriptions,
  ]) {
    for (final field in roots.values) {
      final target = DVGraphQL.typeNamed(field.type);
      final component = target == null ? null : componentOf[target.name];
      final fieldDepth = component == null ? 1 : levelOf(component) + 1;
      if (fieldDepth > depth) depth = fieldDepth;
    }
  }
  return depth;
}

/// What it costs to ask for the whole schema once, one relation deep.
///
/// Every root field with every field of its type, and every relation of that
/// type with its own scalars: the most a client can want without repeating
/// itself through aliases or walking the graph. Computed in one pass per
/// field pair rather than per path.
int _computeAutoMaxCost(int defaultPageSize) {
  int whole(DVGraphQLField field, int relationsLeft) {
    final target = DVGraphQL.typeNamed(field.type);
    var children = 0;
    if (target != null) {
      for (final sub in target.fields.values) {
        final isRelation = DVGraphQL.typeNamed(sub.type) != null;
        if (isRelation && relationsLeft == 0) continue;
        children = _addCost(
          children,
          whole(sub, isRelation ? relationsLeft - 1 : 0),
        );
      }
    }
    final multiplier =
        _isList(field) ? (field.pageSize ?? defaultPageSize) : 1;
    return _multiplyCost(multiplier, _addCost(_ownCost(field), children));
  }

  var cost = 0;
  for (final roots in <Map<String, DVGraphQLField>>[
    DVGraphQL._queries,
    DVGraphQL._mutations,
    DVGraphQL._subscriptions,
  ]) {
    for (final field in roots.values) {
      cost = _addCost(cost, whole(field, 1));
    }
  }
  return cost < 1 ? 1 : cost;
}

/// The response refusing [operation], or null when it may run.
Map<String, Object?>? _edgeRefusal(
  _ParsedDocument parsed,
  _Operation operation,
  Map<String, Object?> variables, {
  required bool authenticated,
}) {
  final limits = DVGraphQL.limits;
  final context = _ExecutionContext(
    variables: variables,
    fragments: parsed.fragments,
    errors: <Map<String, Object?>>[],
  );

  final DVGraphQLQueryCost measured;
  try {
    // Pricing first: it is what proves the fragments acyclic, and every
    // later walk expands them.
    measured = _CostAnalyzer(context, limits).operation(operation);
    for (final selection in context.expand(operation.selections)) {
      if (selection.name != '__schema' && selection.name != '__type') {
        continue;
      }
      final answered = switch (limits.introspection) {
        DVGraphQLIntrospection.never => false,
        DVGraphQLIntrospection.development => !limits.production,
        DVGraphQLIntrospection.authenticated => authenticated,
      };
      if (answered) break;
      return <String, Object?>{
        'errors': <Object?>[
          <String, Object?>{
            'message': 'Introspection is not answered here '
                '(introspection: ${limits.introspection.name}).',
          },
        ],
      };
    }
  } on FormatException catch (error) {
    return <String, Object?>{
      'errors': <Object?>[
        <String, Object?>{'message': error.message},
      ],
    };
  }

  final maxDepth = limits.maxDepth ?? DVGraphQL.autoMaxDepth;
  if (measured.depth > maxDepth) {
    return _refuse(DVGraphQLRefusal(
      budget: 'depth',
      limit: maxDepth,
      actual: measured.depth,
    ));
  }
  final maxCost = limits.maxCost ?? DVGraphQL.autoMaxCost;
  if (measured.cost > maxCost) {
    return _refuse(DVGraphQLRefusal(
      budget: 'cost',
      limit: maxCost,
      actual: measured.cost,
    ));
  }
  return null;
}

Map<String, Object?> _refuse(DVGraphQLRefusal refusal) {
  DVObservability.log(
    refusal.message,
    level: DVLogLevel.warn,
    code: refusal.code,
  );
  return refusal.toResponse();
}

/// The document to run for a request, or the response refusing it.
(String?, Map<String, Object?>?) _persistedDocument(
  String document,
  String? hash,
) {
  final queries = DVGraphQL.persistedQueries;
  final mode = queries.mode;

  if (hash != null && hash.isNotEmpty) {
    if (document.isEmpty) {
      final known = queries.documentFor(hash);
      if (known != null) return (known, null);
      if (mode != DVPersistedQueryMode.require) {
        // The automatic-persisted-query answer: the client resends the
        // document with its hash.
        return (
          null,
          <String, Object?>{
            'errors': <Object?>[
              <String, Object?>{
                'message': 'PersistedQueryNotFound',
                'extensions': <String, Object?>{
                  'code': 'PERSISTED_QUERY_NOT_FOUND',
                },
              },
            ],
          },
        );
      }
      return (
        null,
        _manifestRefusal('no document is persisted under that hash'),
      );
    }
    if (mode != DVPersistedQueryMode.off &&
        DVPersistedQueries.hashOf(document) != hash.toLowerCase()) {
      // Otherwise a trusted hash carries any document past the allow-list.
      return (
        null,
        _manifestRefusal('the hash is not the hash of the document'),
      );
    }
  }

  if (mode == DVPersistedQueryMode.require &&
      queries.documentFor(DVPersistedQueries.hashOf(document)) == null) {
    return (null, _manifestRefusal('the document is not in the manifest'));
  }
  return (document, null);
}

Map<String, Object?> _manifestRefusal(String why) {
  final message = 'Refused: this endpoint answers only persisted queries, and '
      '$why.';
  DVObservability.log(message, level: DVLogLevel.warn, code: 'DV-EDGE-002');
  return <String, Object?>{
    'errors': <Object?>[
      <String, Object?>{
        'message': message,
        'extensions': <String, Object?>{'code': 'DV-EDGE-002'},
      },
    ],
  };
}
