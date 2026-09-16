/// What `dartvel.api.graphql` says, for the generated backend.
///
/// The runtime has depth and cost budgets, an introspection policy and
/// persisted-query enforcement, and the CLI read none of them from
/// pubspec.yaml. `persistedQueries: require` written down to lock the
/// endpoint to known documents did nothing, and nothing said so.
///
/// Every value is checked against what the runtime can use, and a key
/// nothing reads stops the build: each one is a limit somebody wrote down on
/// purpose, and a misspelling that leaves the default in place is the failure
/// worth refusing.
library;

import 'package:dartvel_core/dartvel.dart'
    show DVGraphQLIntrospection, DVPersistedQueryMode;

/// `dartvel.api.graphql`, as declared.
class DVGraphQLApiOptions {
  const DVGraphQLApiOptions({
    this.maxDepth,
    this.maxCost,
    this.introspection = DVGraphQLIntrospection.development,
    this.persistedQueries = DVPersistedQueryMode.off,
  });

  /// The depth budget, or null for `auto`.
  final int? maxDepth;

  /// The cost budget, or null for `auto`.
  final int? maxCost;

  final DVGraphQLIntrospection introspection;

  final DVPersistedQueryMode persistedQueries;

  static const List<String> _apiKeys = <String>['graphql'];
  static const List<String> _graphqlKeys = <String>[
    'maxDepth',
    'maxCost',
    'introspection',
    'persistedQueries',
  ];

  /// Reads `dartvel.api.graphql` out of the `dartvel:` section, or null when
  /// the project declares none.
  ///
  /// Throws a [FormatException] naming the key.
  static DVGraphQLApiOptions? parse(Object? dv) {
    final Object? api = dv is Map ? dv['api'] : null;
    if (api == null) return null;
    if (api is! Map) {
      throw FormatException(
        'dartvel.api must be a map with a graphql: section, not "$api".',
      );
    }
    _refuseUnknown(api, _apiKeys, 'dartvel.api');
    if (!api.containsKey('graphql')) return null;
    final Object? graphql = api['graphql'];
    if (graphql == null) return const DVGraphQLApiOptions();
    if (graphql is! Map) {
      throw FormatException(
        'dartvel.api.graphql must be a map of maxDepth, maxCost, '
        'introspection and persistedQueries, not "$graphql".',
      );
    }
    _refuseUnknown(graphql, _graphqlKeys, 'dartvel.api.graphql');
    return DVGraphQLApiOptions(
      maxDepth: _budget(graphql['maxDepth'], 'maxDepth'),
      maxCost: _budget(graphql['maxCost'], 'maxCost'),
      introspection: _choice(
        graphql['introspection'],
        'introspection',
        DVGraphQLIntrospection.values,
        DVGraphQLIntrospection.development,
      ),
      persistedQueries: _choice(
        graphql['persistedQueries'],
        'persistedQueries',
        DVPersistedQueryMode.values,
        DVPersistedQueryMode.off,
      ),
    );
  }

  /// The statements that install these settings, for the start of the
  /// generated `buildBackendRouter`.
  ///
  /// The page size is kept from the runtime, since this section does not
  /// declare one, and the persisted-query manifest keeps the documents it
  /// holds: only its mode is what the project declared.
  String get installSource =>
      '  core.DVGraphQL.limits = core.DVGraphQLLimits(maxDepth: $maxDepth, '
      'maxCost: $maxCost, '
      'defaultPageSize: core.DVGraphQL.limits.defaultPageSize, '
      'introspection: core.DVGraphQLIntrospection.${introspection.name});\n'
      '  core.DVGraphQL.persistedQueries = core.DVGraphQL.persistedQueries'
      '.withMode(core.DVPersistedQueryMode.${persistedQueries.name});\n';

  static void _refuseUnknown(Map<Object?, Object?> node, List<String> known,
      String where) {
    for (final Object? key in node.keys) {
      if (!known.contains(key)) {
        throw FormatException(
          '$where.$key is not a setting Dartvel reads. $where takes '
          '${known.join(', ')}.',
        );
      }
    }
  }

  static int? _budget(Object? node, String key) {
    if (node == null || node == 'auto') return null;
    // A quoted "7" is text in YAML; reading it as a number would accept what
    // the runtime's constant cannot be, and reading it as auto would replace
    // a limit somebody chose with a derived one.
    if (node is! int || node < 1) {
      throw FormatException(
        'dartvel.api.graphql.$key must be auto or a whole number of at least '
        '1, not "$node".',
      );
    }
    return node;
  }

  static T _choice<T extends Enum>(
    Object? node,
    String key,
    List<T> values,
    T fallback,
  ) {
    if (node == null) return fallback;
    for (final T value in values) {
      if (node is String && value.name == node) return value;
    }
    throw FormatException(
      'dartvel.api.graphql.$key must be one of '
      '${values.map((T value) => value.name).join(', ')}, not "$node".',
    );
  }
}
