/// What `dartvel.server` says, for the generated `startBackend`.
///
/// CORS and compression are two of the specification's built-in middlewares,
/// and declaring either as a route middleware fails the build. The refusal
/// is right -- both are decided once, when the server starts, so a per-route
/// declaration cannot change anything -- but the reason it gave was advice
/// nobody could take: "pass cors: to the serve call". Nobody using Dartvel
/// writes a serve call. The generated `startBackend` does, and it read no
/// configuration at all, so a Dartvel application could not set a CORS
/// policy and could not turn compression off.
///
/// So this reads `dartvel.server`, beside the host and port that were
/// already there, and the generator emits the answer into the call.
library;

/// A CORS policy, as configured.
class DVCorsSettings {
  const DVCorsSettings({
    this.allowAnyOrigin = false,
    this.origins = const <String>[],
    this.allowAnyMethod = false,
    this.methods = const <String>[],
    this.allowAnyHeader = false,
    this.headers = const <String>[],
    this.exposeHeaders = const <String>[],
    this.allowCredentials = false,
    this.maxAgeSeconds,
  });

  final bool allowAnyOrigin;
  final List<String> origins;
  final bool allowAnyMethod;
  final List<String> methods;
  final bool allowAnyHeader;
  final List<String> headers;
  final List<String> exposeHeaders;
  final bool allowCredentials;
  final int? maxAgeSeconds;
}

/// What `dartvel.server` decides for the whole server.
class DVServerOptions {
  const DVServerOptions({this.cors, this.compression = true});

  /// The configured policy, or null when the project said nothing.
  ///
  /// Null means no CORS headers rather than "allow everything": a server
  /// that answers every origin is the single setting most likely to be
  /// wrong, and defaulting to it would put it on every application that
  /// never thought about the question.
  final DVCorsSettings? cors;

  /// On unless the project turns it off.
  final bool compression;

  /// The `dv.CorsOptions(...)` literal for the generated backend, or null.
  String? get corsSource {
    final DVCorsSettings? settings = cors;
    if (settings == null) return null;
    final List<String> fields = <String>[
      if (settings.allowAnyOrigin) 'allowAnyOrigin: true',
      if (settings.origins.isNotEmpty)
        'origins: ${_stringList(settings.origins)}',
      if (settings.allowAnyMethod) 'allowAnyMethod: true',
      if (settings.methods.isNotEmpty)
        'methods: ${_stringList(settings.methods)}',
      if (settings.allowAnyHeader) 'allowAnyHeader: true',
      if (settings.headers.isNotEmpty)
        'headers: ${_stringList(settings.headers)}',
      if (settings.exposeHeaders.isNotEmpty)
        'exposeHeaders: ${_stringList(settings.exposeHeaders)}',
      if (settings.allowCredentials) 'allowCredentials: true',
      if (settings.maxAgeSeconds != null)
        'maxAge: Duration(seconds: ${settings.maxAgeSeconds})',
    ];
    return 'dv.CorsOptions(${fields.join(', ')})';
  }

  /// Read `dartvel.server` out of the `dartvel:` section of a pubspec.
  ///
  /// Throws a [FormatException] naming the key rather than carrying on with
  /// a default, because every value here is a security or delivery decision
  /// somebody wrote down deliberately. A misspelling that silently leaves
  /// the default in place is the failure mode worth refusing.
  static DVServerOptions parse(Object? dv) {
    final Object? server = _value(dv, 'server');
    if (server == null) return const DVServerOptions();

    final Object? compression = _value(server, 'compression');
    if (compression != null && compression is! bool) {
      throw FormatException(
        'dartvel.server.compression must be true or false, not '
        '"$compression". A string is not a boolean, and ignoring it would '
        'leave compression on for somebody who wrote down that they wanted '
        'it off.',
      );
    }

    return DVServerOptions(
      cors: _cors(_value(server, 'cors')),
      compression: compression is bool ? compression : true,
    );
  }

  static DVCorsSettings? _cors(Object? node) {
    if (node == null) return null;
    if (node is bool) {
      // cors: true is not a policy. Say which origins.
      throw const FormatException(
        'dartvel.server.cors takes a policy, not a boolean. Name the origins '
        'you answer -- origins: [https://app.example.com] -- or origins: any '
        'if this really is a public API.',
      );
    }

    final (bool anyOrigin, List<String> origins) =
        _originList(_value(node, 'origins'), 'origins');
    final (bool anyMethod, List<String> methods) =
        _wildcardList(_value(node, 'methods'), 'methods');
    final (bool anyHeader, List<String> headers) =
        _wildcardList(_value(node, 'headers'), 'headers');
    final (bool _, List<String> exposeHeaders) =
        _wildcardList(_value(node, 'exposeHeaders'), 'exposeHeaders');
    final bool credentials = _bool(_value(node, 'allowCredentials'),
        'dartvel.server.cors.allowCredentials');

    // The browser refuses this combination itself: Access-Control-Allow-
    // Origin: * with credentials is not a policy, it is a request that is
    // never sent. Refused here, naming both keys, rather than emitted as an
    // assertion that fires from inside a generated file.
    if (credentials && anyOrigin) {
      throw const FormatException(
        'dartvel.server.cors: allowCredentials cannot be used with '
        'origins: any. A browser will not send credentials to a wildcard '
        'origin, so this policy allows nothing at all. Name the origins '
        'that may send them.',
      );
    }

    return DVCorsSettings(
      allowAnyOrigin: anyOrigin,
      origins: origins,
      allowAnyMethod: anyMethod,
      methods: methods,
      allowAnyHeader: anyHeader,
      headers: headers,
      exposeHeaders: exposeHeaders,
      allowCredentials: credentials,
      maxAgeSeconds: _seconds(_value(node, 'maxAge')),
    );
  }

  /// An origin list, refusing anything that is not an origin.
  ///
  /// The browser compares the `Origin` header, which is scheme, host and
  /// port and nothing else -- so a path or a trailing slash never matches
  /// anything, and a policy that silently matches nothing reads as CORS
  /// being broken rather than as a typo.
  static (bool, List<String>) _originList(Object? node, String key) {
    final (bool any, List<String> values) = _wildcardList(node, key);
    for (final String origin in values) {
      final Uri? parsed = Uri.tryParse(origin);
      if (parsed == null ||
          !parsed.hasScheme ||
          parsed.host.isEmpty ||
          parsed.path.isNotEmpty ||
          parsed.hasQuery ||
          parsed.hasFragment) {
        throw FormatException(
          'dartvel.server.cors.origins: "$origin" is not an origin. A '
          'browser sends scheme, host and port -- '
          'https://app.example.com, with no trailing slash and no path -- '
          'and anything else never matches.',
        );
      }
    }
    return (any, values);
  }

  static (bool, List<String>) _wildcardList(Object? node, String key) {
    if (node == null) return (false, const <String>[]);
    if (node is String) {
      if (node == 'any' || node == '*') return (true, const <String>[]);
      return (false, <String>[node]);
    }
    if (node is Iterable) {
      final List<String> values = node
          .map((Object? e) => e?.toString() ?? '')
          .where((String e) => e.isNotEmpty)
          .toList(growable: false);
      if (values.length == 1 && (values.first == 'any' || values.first == '*')) {
        return (true, const <String>[]);
      }
      return (false, values);
    }
    throw FormatException(
      'dartvel.server.cors.$key must be a list or the word any, not '
      '"$node".',
    );
  }

  static bool _bool(Object? node, String where) {
    if (node == null) return false;
    if (node is bool) return node;
    throw FormatException('$where must be true or false, not "$node".');
  }

  /// Seconds, from a number or from a duration somebody wrote as `10m`.
  static int? _seconds(Object? node) {
    if (node == null) return null;
    if (node is num) return node.toInt();
    final String text = node.toString().trim();
    final RegExpMatch? match =
        RegExp(r'^(\d+)\s*(s|m|h)?$').firstMatch(text);
    if (match == null) {
      throw FormatException(
        'dartvel.server.cors.maxAge must be a number of seconds, or a '
        'duration such as 10m, not "$text".',
      );
    }
    final int value = int.parse(match.group(1)!);
    switch (match.group(2)) {
      case 'm':
        return value * 60;
      case 'h':
        return value * 3600;
      default:
        return value;
    }
  }

  static Object? _value(Object? node, String key) =>
      node is Map ? node[key] : null;
}

String _stringList(List<String> values) =>
    "<String>[${values.map((String v) => "'${v.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'").join(', ')}]";
