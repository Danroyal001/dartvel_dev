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

import 'package:dartvel_core/dartvel.dart'
    show DVCidr, DVClientAddress, DVForwardedHeader, dvDefaultMaxBodyBytes;

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
  const DVServerOptions({
    this.cors,
    this.compression = true,
    this.trustedProxies = const <String>[],
    this.forwardedHeader,
    this.ipv6SourcePrefix = DVClientAddress.defaultIpv6SourcePrefix,
    this.maxBodyBytes = dvDefaultMaxBodyBytes,
  });

  final int maxBodyBytes;

  /// The configured policy, or null when the project said nothing.
  ///
  /// Null means no CORS headers rather than "allow everything": a server
  /// that answers every origin is the single setting most likely to be
  /// wrong, and defaulting to it would put it on every application that
  /// never thought about the question.
  final DVCorsSettings? cors;

  /// On unless the project turns it off.
  final bool compression;

  /// The proxies whose forwarded client address is believed, as ranges:
  /// `dartvel.server.trustedProxies`. Empty trusts none, and the client
  /// address is the connection's peer.
  ///
  /// Checked with the runtime's own parser, so what the build accepts is
  /// exactly what the server reads: a range it could not read, or would read
  /// as something wider, is refused here rather than at the first request.
  final List<String> trustedProxies;

  /// Which header those proxies write, `x-forwarded-for` or `forwarded`; null
  /// is the runtime's default, `x-forwarded-for`.
  final String? forwardedHeader;

  /// How many leading bits of an IPv6 client address count as one source:
  /// `dartvel.server.ipv6SourcePrefix`, 64 unless the project says otherwise.
  /// Checked with the runtime's own rule, from 32 to 128.
  final int ipv6SourcePrefix;

  /// The `dartvelTrustedProxies` literal for the generated backend.
  String get trustedProxiesSource => _stringList(trustedProxies);

  /// The `dartvelForwardedHeader` literal for the generated backend.
  String get forwardedHeaderSource {
    final String? header = forwardedHeader;
    return header == null ? 'null' : "'$header'";
  }

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
      trustedProxies: _trustedProxies(_value(server, 'trustedProxies')),
      forwardedHeader: _forwardedHeader(_value(server, 'forwardedHeader')),
      ipv6SourcePrefix: _ipv6SourcePrefix(_value(server, 'ipv6SourcePrefix')),
      maxBodyBytes: _maxBodyBytes(_value(server, 'maxBodyBytes')),
    );
  }

  static int _maxBodyBytes(Object? node) {
    if (node == null) return dvDefaultMaxBodyBytes;
    // A whole number only. A quoted "65536" is text in YAML, and "16MB" is
    // a unit this does not read; accepting either as the default would be a
    // limit somebody wrote down and did not get.
    if (node is! int || node <= 0) {
      throw FormatException(
        'dartvel.server.maxBodyBytes must be a positive whole number of '
        'bytes, such as 1048576, not "$node". It is the largest request body '
        'the server reads for a route that declares no limit of its own.',
      );
    }
    return node;
  }

  static int _ipv6SourcePrefix(Object? node) {
    if (node == null) return DVClientAddress.defaultIpv6SourcePrefix;
    // A quoted "64" is refused too: YAML makes it text, and reading text as a
    // number here would accept what the runtime's constant cannot be.
    if (node is! int) {
      throw FormatException(
        'dartvel.server.ipv6SourcePrefix must be a whole number of bits from '
        '${DVClientAddress.minIpv6SourcePrefix} to 128, such as 64, not '
        '"$node".',
      );
    }
    try {
      return DVClientAddress.checkIpv6SourcePrefix(node);
    } on FormatException catch (error) {
      throw FormatException('dartvel.server.${error.message}');
    }
  }

  static List<String> _trustedProxies(Object? node) {
    if (node == null) return const <String>[];
    if (node is! Iterable) {
      throw FormatException(
        'dartvel.server.trustedProxies must be a list of address ranges, '
        'such as [127.0.0.1/32, "::1/128"], not "$node".',
      );
    }
    final List<String> ranges = <String>[];
    for (final Object? entry in node) {
      if (entry is! String) {
        throw FormatException(
          'dartvel.server.trustedProxies: "$entry" is not an address range. '
          'Quote it; YAML reads some values as something other than text.',
        );
      }
      try {
        DVCidr.parse(entry.trim());
      } on FormatException catch (error) {
        throw FormatException(
          'dartvel.server.trustedProxies: ${error.message} A proxy listed here '
          'is believed about who its clients are, so a wrong range trusts the '
          'wrong machines.',
        );
      }
      ranges.add(entry.trim());
    }
    return List<String>.unmodifiable(ranges);
  }

  static String? _forwardedHeader(Object? node) {
    if (node == null) return null;
    try {
      return DVForwardedHeader.parse('$node').headerName;
    } on FormatException catch (error) {
      throw FormatException('dartvel.server.${error.message}');
    }
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
    final (bool anyExposed, List<String> exposeHeaders) =
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

    if (credentials) {
      _checkCredentialed(
        origins: origins,
        wildcards: <String, bool>{
          'methods': anyMethod,
          'headers': anyHeader,
          'exposeHeaders': anyExposed,
        },
      );
    }

    return DVCorsSettings(
      allowAnyOrigin: anyOrigin,
      origins: origins,
      allowAnyMethod: anyMethod,
      methods: methods,
      allowAnyHeader: anyHeader,
      headers: credentials ? _withClientHeaders(headers) : headers,
      exposeHeaders: exposeHeaders,
      allowCredentials: credentials,
      maxAgeSeconds: _seconds(_value(node, 'maxAge')),
    );
  }

  /// The request headers the generated client sends on a call from a
  /// browser: the body's type, and the CSRF token every state-changing call
  /// carries. A credentialed policy that did not answer them would fail the
  /// preflight of every sign-in.
  static const List<String> clientRequestHeaders = <String>[
    'content-type',
    'x-dartvel-csrf-token',
  ];

  static List<String> _withClientHeaders(List<String> headers) {
    final Set<String> listed = <String>{
      for (final String h in headers) h.toLowerCase(),
    };
    return <String>[
      ...headers,
      for (final String h in clientRequestHeaders)
        if (!listed.contains(h)) h,
    ];
  }

  /// Refuses a credentialed policy that could never work, or that hands the
  /// signed-in person to a page anybody on the network can rewrite.
  static void _checkCredentialed({
    required List<String> origins,
    required Map<String, bool> wildcards,
  }) {
    if (origins.isEmpty) {
      throw const FormatException(
        'dartvel.server.cors.origins is empty and allowCredentials is true. '
        'Credentials are answered only for origins named exactly -- '
        'origins: [https://app.example.com] -- so this policy allows nothing.',
      );
    }
    for (final MapEntry<String, bool> wildcard in wildcards.entries) {
      if (wildcard.value) {
        throw FormatException(
          'dartvel.server.cors.${wildcard.key}: any cannot be used with '
          'allowCredentials. A browser reads "*" as a literal name once '
          'credentials are on, so nothing would match; list the '
          '${wildcard.key} instead.',
        );
      }
    }
    for (final String origin in origins) {
      final Uri uri = Uri.parse(origin);
      final bool loopback = uri.host == 'localhost' ||
          uri.host == '127.0.0.1' ||
          uri.host == '[::1]' ||
          uri.host == '::1';
      if (uri.scheme != 'https' && !loopback) {
        throw FormatException(
          'dartvel.server.cors.origins: "$origin" is not https and '
          'allowCredentials is true. A page served over plain http can be '
          'rewritten by anybody on the network into one that acts as the '
          'signed-in person. Only a loopback origin may be http.',
        );
      }
    }
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
