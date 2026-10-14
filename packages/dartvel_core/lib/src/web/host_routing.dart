/// Inbound Host-based routing for multi-domain Dartvel applications.
///
/// One web-server binary serves multiple host patterns (e.g. `sigmadev.digital`,
/// `tools.sigmadev.digital`, and `*.tools.sigmadev.digital`), mapping each host
/// to its respective route mount while preserving the browser's address bar.
library;

/// Whether [host] is a valid DNS hostname under RFC 1123.
bool dvIsValidDomain(String host) {
  if (host.isEmpty || host.length > 253) return false;
  final List<String> labels = host.split('.');
  if (labels.isEmpty) return false;
  for (final String label in labels) {
    if (label.isEmpty || label.length > 63) return false;
    if (label.startsWith('-') || label.endsWith('-')) return false;
    for (int i = 0; i < label.length; i++) {
      final int code = label.codeUnitAt(i);
      final bool isAlpha = (code >= 97 && code <= 122) || (code >= 65 && code <= 90);
      final bool isDigit = code >= 48 && code <= 57;
      final bool isHyphen = code == 45;
      if (!isAlpha && !isDigit && !isHyphen) return false;
    }
  }
  return true;
}

/// Normalises [rawHost] by stripping ports, trailing dots, whitespace, and
/// converting to lowercase ASCII. Returns null if invalid or missing.
String? dvNormalizeHost(String? rawHost) {
  if (rawHost == null) return null;
  var host = rawHost.trim();
  if (host.isEmpty) return null;
  if (host.endsWith('.')) {
    host = host.substring(0, host.length - 1);
  }
  if (host.contains(':')) {
    final parts = host.split(':');
    if (parts.length != 2) return null;
    final port = int.tryParse(parts[1]);
    if (port == null || port < 1 || port > 65535) return null;
    host = parts[0];
  }
  host = host.toLowerCase();
  if (!dvIsValidDomain(host)) return null;
  return host;
}

/// Extracts the validated host from request [headers], respecting
/// `x-forwarded-host` only when [remoteAddress] is in [trustedProxies]
/// (or [trustLoopback] is true for loopback addresses).
String? dvExtractHost(
  Map<String, String> headers, {
  Set<String> trustedProxies = const <String>{},
  bool trustLoopback = false,
  String? remoteAddress,
}) {
  bool isTrusted = false;
  if (remoteAddress != null) {
    final cleanRemote = remoteAddress.split(':').first;
    if (trustedProxies.contains(cleanRemote)) {
      isTrusted = true;
    } else if (trustLoopback &&
        (cleanRemote == '127.0.0.1' || cleanRemote == '::1' || cleanRemote == 'localhost')) {
      isTrusted = true;
    }
  }

  if (isTrusted) {
    final xForwarded = headers['x-forwarded-host'];
    if (xForwarded != null && xForwarded.isNotEmpty) {
      final first = xForwarded.split(',').first.trim();
      final norm = dvNormalizeHost(first);
      if (norm != null) return norm;
    }
  }

  final hostHeader = headers['host'];
  return dvNormalizeHost(hostHeader);
}

/// A declared host pattern in `dartvel.hosts`.
final class DVHostEntry {
  const DVHostEntry({
    required this.pattern,
    this.siteUrl,
    this.mount,
    this.routes,
    this.legacyRedirects = const <String, String>{},
    this.name,
    this.description,
  });

  /// The declared pattern (e.g. `'sigmadev.digital'`, `'tools.sigmadev.digital'`,
  /// or `'*.tools.sigmadev.digital'`).
  final String pattern;

  /// The public origin for this host (e.g. `'https://tools.sigmadev.digital'` or
  /// `'https://{slug}.tools.sigmadev.digital'`).
  final String? siteUrl;

  /// Route mount prefix on this host. E.g. `'/tools'` maps `'/'` on this host
  /// to internal route `'/tools'`.
  final String? mount;

  /// Optional set of route patterns allowed on this host.
  final Set<String>? routes;

  /// Legacy redirects declared on this host.
  final Map<String, String> legacyRedirects;

  /// Site name override for SEO on this host.
  final String? name;

  /// Site description override for SEO on this host.
  final String? description;

  bool get isWildcard => pattern.startsWith('*.');

  /// The wildcard suffix (e.g. `'.tools.sigmadev.digital'`).
  String get wildcardSuffix => isWildcard ? pattern.substring(1) : '';

  Map<String, Object?> toJson() => <String, Object?>{
        'pattern': pattern,
        if (siteUrl != null) 'siteUrl': siteUrl,
        if (mount != null) 'mount': mount,
        if (routes != null) 'routes': routes!.toList(),
        if (legacyRedirects.isNotEmpty) 'legacyRedirects': legacyRedirects,
        if (name != null) 'name': name,
        if (description != null) 'description': description,
      };

  factory DVHostEntry.fromJson(Map<String, Object?> json) => DVHostEntry(
        pattern: json['pattern']! as String,
        siteUrl: json['siteUrl'] as String?,
        mount: json['mount'] as String?,
        routes: json['routes'] is List
            ? (json['routes']! as List).map((e) => '$e').toSet()
            : null,
        legacyRedirects: json['legacyRedirects'] is Map
            ? (json['legacyRedirects']! as Map).map((k, v) => MapEntry('$k', '$v'))
            : const <String, String>{},
        name: json['name'] as String?,
        description: json['description'] as String?,
      );
}

/// Project host routing configuration.
final class DVHostRoutingConfig {
  const DVHostRoutingConfig({
    this.trustedProxies = const <String>{},
    this.trustLoopback = false,
    this.entries = const <DVHostEntry>[],
  });

  final Set<String> trustedProxies;
  final bool trustLoopback;
  final List<DVHostEntry> entries;

  bool get isEmpty => entries.isEmpty;
  bool get isNotEmpty => entries.isNotEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
        if (trustedProxies.isNotEmpty) 'trustedProxies': trustedProxies.toList(),
        if (trustLoopback) 'trustLoopback': true,
        'entries': entries.map((e) => e.toJson()).toList(),
      };

  factory DVHostRoutingConfig.fromJson(Map<String, Object?> json) => DVHostRoutingConfig(
        trustedProxies: json['trustedProxies'] is List
            ? (json['trustedProxies']! as List).map((e) => '$e').toSet()
            : const <String>{},
        trustLoopback: json['trustLoopback'] == true,
        entries: json['entries'] is List
            ? (json['entries']! as List)
                .whereType<Map>()
                .map((e) => DVHostEntry.fromJson(e.cast<String, Object?>()))
                .toList()
            : const <DVHostEntry>[],
      );

  static DVHostRoutingConfig parse(Object? section, {List<String>? problems}) {
    if (section == null) return const DVHostRoutingConfig();
    if (section is! Map) {
      problems?.add('dartvel.hosts must be a map of host declarations.');
      return const DVHostRoutingConfig();
    }
    final Set<String> trusted = <String>{};
    bool loopback = false;
    final Object? proxies = section['trustedProxies'];
    if (proxies is List) {
      for (final Object? p in proxies) {
        if (p is String) trusted.add(p);
      }
    } else if (proxies == true || proxies == 'loopback') {
      loopback = true;
    }

    final List<DVHostEntry> entries = <DVHostEntry>[];
    final Object? rawEntries = section['entries'] ?? section;
    if (rawEntries is Map) {
      for (final MapEntry<Object?, Object?> e in rawEntries.entries) {
        final String key = '${e.key}'.trim();
        if (key == 'trustedProxies' || key == 'trustLoopback' || key == 'entries') {
          continue;
        }
        final Object? val = e.value;
        final Map<String, Object?> map =
            val is Map ? val.cast<String, Object?>() : <String, Object?>{};

        final String pattern = key.toLowerCase();
        if (pattern.startsWith('*.')) {
          final String rest = pattern.substring(2);
          if (rest.contains('*') || !dvIsValidDomain(rest)) {
            problems?.add('dartvel.hosts: "$key" is an invalid wildcard host pattern.');
            continue;
          }
        } else if (!dvIsValidDomain(pattern)) {
          problems?.add('dartvel.hosts: "$key" is not a valid hostname.');
          continue;
        }

        entries.add(DVHostEntry(
          pattern: pattern,
          siteUrl: map['siteUrl'] as String?,
          mount: map['mount'] as String?,
          routes: map['routes'] is List
              ? (map['routes']! as List).map((r) => '$r').toSet()
              : null,
          legacyRedirects: map['legacyRedirects'] is Map
              ? (map['legacyRedirects']! as Map).map((k, v) => MapEntry('$k', '$v'))
              : const <String, String>{},
          name: map['name'] as String?,
          description: map['description'] as String?,
        ));
      }
    }
    return DVHostRoutingConfig(
      trustedProxies: trusted,
      trustLoopback: loopback,
      entries: entries,
    );
  }
}

/// A matched host and extracted wildcard captures.
final class DVHostMatch {
  const DVHostMatch({
    required this.entry,
    required this.matchedHost,
    this.captures = const <String, String>{},
  });

  final DVHostEntry entry;
  final String matchedHost;
  final Map<String, String> captures;

  String? get siteUrl {
    final base = entry.siteUrl;
    if (base == null) return null;
    var result = base;
    for (final e in captures.entries) {
      result = result.replaceAll('{${e.key}}', e.value);
    }
    return result;
  }
}

/// Matches [normalizedHost] against [config].
/// Returns null if the host is not recognised or if wildcard has extra labels.
DVHostMatch? dvMatchHost(String normalizedHost, DVHostRoutingConfig config) {
  // 1. Exact match first
  for (final entry in config.entries) {
    if (!entry.isWildcard && entry.pattern == normalizedHost) {
      return DVHostMatch(entry: entry, matchedHost: normalizedHost);
    }
  }
  // 2. Single-label wildcard match
  for (final entry in config.entries) {
    if (entry.isWildcard) {
      final suffix = entry.wildcardSuffix;
      if (normalizedHost.endsWith(suffix) && normalizedHost.length > suffix.length) {
        final prefix = normalizedHost.substring(0, normalizedHost.length - suffix.length);
        // Single-label wildcard: must NOT contain any dot!
        if (!prefix.contains('.') && prefix.isNotEmpty) {
          return DVHostMatch(
            entry: entry,
            matchedHost: normalizedHost,
            captures: <String, String>{'slug': prefix},
          );
        }
      }
    }
  }
  return null;
}

/// Resolves the internal route path from [requestPath] given [match].
String dvResolveHostPath(DVHostMatch match, String requestPath) {
  final clean =
      requestPath.isEmpty ? '/' : (requestPath.startsWith('/') ? requestPath : '/$requestPath');
  final mount = match.entry.mount;
  if (mount == null) return clean;

  var effectiveMount = mount;
  for (final e in match.captures.entries) {
    effectiveMount = effectiveMount.replaceAll('{${e.key}}', e.value);
  }
  if (clean == '/') return effectiveMount;
  final baseMount = effectiveMount.replaceAll(RegExp(r'/+$'), '');
  return '$baseMount$clean';
}

/// Evaluates legacy path redirects on [match] for [rawPath].
/// Only registered slugs in [registeredToolSlugs] will redirect; unregistered paths return null.
String? dvHostLegacyRedirect(
  DVHostMatch match,
  String rawPath, {
  required Set<String> registeredToolSlugs,
  String toolsIndexOrigin = 'https://tools.sigmadev.digital',
  String toolSubdomainPattern = 'https://{slug}.tools.sigmadev.digital',
}) {
  final pathOnly = rawPath.split('?').first;
  final clean = pathOnly == '/' ? '/' : pathOnly.replaceAll(RegExp(r'/+$'), '');

  // Exact tools index path
  if (clean == '/tools') {
    final query = rawPath.contains('?') ? '?${rawPath.split('?').last}' : '';
    return '$toolsIndexOrigin/$query';
  }

  // /tools/<slug>
  final matchSlug = RegExp(r'^/tools/([^/]+)$').firstMatch(clean);
  if (matchSlug != null) {
    final slug = matchSlug.group(1)!;
    if (registeredToolSlugs.contains(slug)) {
      final origin = toolSubdomainPattern.replaceAll('{slug}', slug);
      final query = rawPath.contains('?') ? '?${rawPath.split('?').last}' : '';
      return '$origin/$query';
    }
  }

  return null;
}
