/// Inbound host routing: one application, several hostnames, each mapped onto
/// a part of the one route tree.
///
/// Declared under `dartvel.hosts` in pubspec.yaml:
///
/// ```yaml
/// dartvel:
///   hosts:
///     example.com:                 # no mount: the primary host
///       siteUrl: https://example.com
///     docs.example.com:
///       mount: /docs               # docs.example.com/x <-> /docs/x
///       siteUrl: https://docs.example.com
///     '*.apps.example.com':
///       mount: /apps/{label}
///       siteUrl: https://{label}.apps.example.com
/// ```
///
/// Pure Dart with no `dart:io`, because the server, the CLI's preview server
/// and the Flutter web client all answer the same two questions with it:
/// which part of the route tree does this host show, and on which host does
/// this route live.
library;

/// One `dartvel.hosts` entry.
///
/// [pattern] is a hostname (`docs.example.com`) or a single leftmost-label
/// wildcard (`*.apps.example.com`). [mount] is where in the route tree the
/// host's `/` is, `/` for the primary host; in a wildcard entry `{label}`
/// stands for the label the host matched, as a whole path segment. [siteUrl]
/// is the host's public origin and may use `{label}` the same way.
final class const DVHostEntry({
  required final String pattern,
  required final String siteUrl,
  final String mount = '/',
  final String? name,
  final String? description,
}) {
  /// Whether [pattern] is `*.<suffix>`.
  bool get isWildcard => pattern.startsWith('*.');

  /// The primary host is the one whose mount is the root.
  bool get isPrimary => mount == '/';

  Map<String, Object?> toJson() => <String, Object?>{
    'pattern': pattern,
    'siteUrl': siteUrl,
    'mount': mount,
    if (name != null) 'name': name,
    if (description != null) 'description': description,
  };

  static DVHostEntry fromJson(Map<Object?, Object?> json) => DVHostEntry(
    pattern: '${json['pattern']}',
    siteUrl: '${json['siteUrl']}',
    mount: json['mount'] is String ? json['mount']! as String : '/',
    name: json['name'] as String?,
    description: json['description'] as String?,
  );
}

/// A `dartvel.hosts` entry that only redirects: a domain kept for its links
/// that now lives elsewhere. [paths] are exact paths sent somewhere of their
/// own; every other path goes to [to], or is not redirected when [to] is null.
/// Answered with a 301 before any routing, and invisible to everything else
/// hosts do: mounts, canonical URLs, sitemaps.
final class const DVHostRedirect({
  required final String pattern,
  final String? to,
  final Map<String, String> paths = const <String, String>{},
}) {
  Map<String, Object?> toJson() => <String, Object?>{
    'pattern': pattern,
    if (to != null) 'to': to,
    if (paths.isNotEmpty) 'paths': paths,
  };

  /// What [DVHosts.redirectsToJson] wrote; empty for anything else.
  static List<DVHostRedirect> listFromJson(Object? json) => json is! List
      ? const <DVHostRedirect>[]
      : <DVHostRedirect>[
          for (final Object? e in json)
            if (e is Map)
              DVHostRedirect(
                pattern: '${e['pattern']}',
                to: e['to'] as String?,
                paths: e['paths'] is Map
                    ? <String, String>{for (final MapEntry<Object?, Object?> p in (e['paths'] as Map).entries) '${p.key}': '${p.value}'}
                    : const <String, String>{},
              ),
        ];
}

/// Where a request for [rawPath] on [host] is redirected by [redirects], or
/// null when that host does not redirect it.
String? dvHostRedirectTarget(List<DVHostRedirect> redirects, {required String? host, required String rawPath}) {
  final String? name = dvNormaliseHost(host);
  if (name == null || redirects.isEmpty) return null;
  for (final DVHostRedirect redirect in redirects) {
    if (redirect.pattern != name) continue;
    return redirect.paths[rawPath] ?? redirect.to;
  }
  return null;
}

/// The entries of `dartvel.hosts`, and the problems found reading them.
typedef DVHostsParse = ({DVHosts hosts, List<String> problems});

/// Every host an application answers on.
///
/// Empty means `dartvel.hosts` was not declared, and then nothing anywhere
/// behaves differently: every function here is only consulted when
/// [isEmpty] is false.
final class const DVHosts(final List<DVHostEntry> entries, {final List<DVHostRedirect> redirectHosts = const <DVHostRedirect>[]}) {
  static const DVHosts none = DVHosts(<DVHostEntry>[]);

  /// The redirecting hosts, for the manifest's `hostRedirects`.
  List<Object?> redirectsToJson() => <Object?>[for (final DVHostRedirect r in redirectHosts) r.toJson()];

  bool get isEmpty => entries.isEmpty;
  bool get isNotEmpty => entries.isNotEmpty;

  /// The entry with no mount. [parse] refuses a configuration without
  /// exactly one, so a [DVHosts] that is not empty always has it.
  DVHostEntry get primary => entries.firstWhere(
    (DVHostEntry e) => e.isPrimary,
    orElse: () => throw StateError('dartvel.hosts has no primary host.'),
  );

  /// The primary host as a match.
  DVHostMatch get primaryMatch => DVHostMatch(primary);

  /// Reads `dartvel.hosts`. [defaultSiteUrl] is `dartvel.seo.siteUrl`, which
  /// the primary host's siteUrl defaults to.
  ///
  /// Nothing is guessed: every problem is reported, and a configuration with
  /// any is one the build refuses.
  static DVHostsParse parse(Object? yaml, {String? defaultSiteUrl}) {
    final List<String> problems = <String>[];
    if (yaml == null) return (hosts: none, problems: problems);
    if (yaml is! Map) {
      problems.add('dartvel.hosts must be a map of hostname: settings.');
      return (hosts: none, problems: problems);
    }
    final List<DVHostEntry> entries = <DVHostEntry>[];
    final List<DVHostRedirect> redirectHosts = <DVHostRedirect>[];
    for (final MapEntry<Object?, Object?> e in yaml.entries) {
      final String pattern = '${e.key}'.trim().toLowerCase();
      final Object? raw = e.value;
      if (raw != null && raw is! Map) {
        problems.add(
          'dartvel.hosts."$pattern" must be a map (mount, siteUrl, name, description).',
        );
        continue;
      }
      final Map<Object?, Object?> settings = raw is Map
          ? raw
          : const <Object?, Object?>{};
      String where(String key) => 'dartvel.hosts."$pattern".$key';

      if (settings.containsKey('redirect') || settings.containsKey('redirects')) {
        final List<String> before = List<String>.of(problems);
        bool target(String value) => value.startsWith('/') || _origin(value, allowPath: true) != null;
        if (pattern.startsWith('*.') || !_ascii(pattern) || !pattern.split('.').every(_isLabel)) {
          problems.add('dartvel.hosts: "$pattern" is not a valid hostname; a redirecting host is one exact name.');
        }
        for (final String key in const <String>['mount', 'siteUrl']) {
          if (settings.containsKey(key)) problems.add('${where(key)}: a redirecting host serves no pages, so it has no $key.');
        }
        final Object? to = settings['redirect'];
        if (to != null && !('$to'.startsWith('https://') || '$to'.startsWith('http://')) ) {
          problems.add('${where('redirect')} must be a full http(s) address, not "$to".');
        }
        final Map<String, String> paths = <String, String>{};
        final Object? rawPaths = settings['redirects'];
        if (rawPaths != null && rawPaths is! Map) {
          problems.add('${where('redirects')} must be a map of path: target.');
        } else if (rawPaths is Map) {
          for (final MapEntry<Object?, Object?> p in rawPaths.entries) {
            final String from = '${p.key}';
            final String value = '${p.value}';
            if (!from.startsWith('/')) {
              problems.add('${where('redirects')}: "$from" must be a path starting with /.');
            } else if (!target(value)) {
              problems.add('${where('redirects')}."$from" must be a path or a full http(s) address, not "$value".');
            } else {
              paths[from] = value;
            }
          }
        }
        if (problems.length == before.length) {
          redirectHosts.add(DVHostRedirect(pattern: pattern, to: to == null ? null : '$to', paths: paths));
        }
        continue;
      }

      final bool wildcard = pattern.startsWith('*.');
      if (!_ascii(pattern)) {
        problems.add(
          'dartvel.hosts: "$pattern" is not ASCII. Write an internationalised name in its punycode (xn--) form.',
        );
        continue;
      }
      final String name = wildcard ? pattern.substring(2) : pattern;
      final List<String> labels = name.split('.');
      if (name.isEmpty || !labels.every(_isLabel)) {
        problems.add(
          wildcard
              ? 'dartvel.hosts: "$pattern" is not a valid wildcard. Only a single leftmost label may be a wildcard: *.apps.example.com.'
              : 'dartvel.hosts: "$pattern" is not a valid hostname.',
        );
        continue;
      }
      if (wildcard && labels.length < 2) {
        problems.add(
          'dartvel.hosts: "$pattern" is too broad; a wildcard needs at least two labels after "*.".',
        );
        continue;
      }

      final Object? mountRaw = settings['mount'];
      final String mount = mountRaw == null ? '/' : '$mountRaw'.trim();
      if (!mount.startsWith('/')) {
        problems.add('${where('mount')} must start with /, not "$mount".');
        continue;
      }
      final String normalisedMount = mount.length > 1
          ? mount.replaceAll(RegExp(r'/+$'), '')
          : mount;
      final bool mountHasLabel = normalisedMount.contains('{label}');
      final Object? siteUrlRaw = settings['siteUrl'];
      String? siteUrl = siteUrlRaw == null ? null : '$siteUrlRaw'.trim();
      final bool siteUrlHasLabel = siteUrl?.contains('{label}') ?? false;
      if (!wildcard && (mountHasLabel || siteUrlHasLabel)) {
        problems.add(
          'dartvel.hosts."$pattern" uses {label}, which only a wildcard (*.) entry has.',
        );
        continue;
      }
      if (mountHasLabel) {
        final List<String> segments = normalisedMount
            .split('/')
            .skip(1)
            .toList();
        final bool whole = segments.every(
          (String s) => !s.contains('{label}') || s == '{label}',
        );
        if (!whole ||
            segments.where((String s) => s == '{label}').length != 1) {
          problems.add(
            '${where('mount')}: {label} must appear once, as a whole path segment (/apps/{label}).',
          );
          continue;
        }
      }
      if (normalisedMount != '/' &&
          normalisedMount
              .split('/')
              .skip(1)
              .any((String s) => s.isEmpty || (s.startsWith(':')))) {
        problems.add(
          '${where('mount')} "$normalisedMount" has an empty or parameter segment.',
        );
        continue;
      }
      if (normalisedMount == '/' && wildcard) {
        problems.add(
          'dartvel.hosts."$pattern": a wildcard host needs a mount containing {label}; the primary host cannot be a wildcard.',
        );
        continue;
      }
      if (wildcard && !mountHasLabel) {
        problems.add(
          '${where('mount')} must contain {label} for a wildcard host, or every label would show the same pages.',
        );
        continue;
      }
      if (normalisedMount == '/') siteUrl ??= defaultSiteUrl;
      if (siteUrl == null || siteUrl.isEmpty) {
        problems.add(
          '${where('siteUrl')} is missing. It is the host\'s public origin, such as https://$name.',
        );
        continue;
      }
      final String? origin = _origin(siteUrl.replaceAll('{label}', 'label'));
      if (origin == null) {
        problems.add(
          '${where('siteUrl')} must be an http(s) origin with no path, query or fragment, not "$siteUrl".',
        );
        continue;
      }
      entries.add(
        DVHostEntry(
          pattern: pattern,
          siteUrl: siteUrl.replaceAll(RegExp(r'/+$'), ''),
          mount: normalisedMount,
          name: settings['name'] == null ? null : '${settings['name']}',
          description: settings['description'] == null
              ? null
              : '${settings['description']}',
        ),
      );
    }
    final List<DVHostEntry> primaries = entries
        .where((DVHostEntry e) => e.isPrimary)
        .toList();
    if (entries.isNotEmpty && primaries.isEmpty && problems.isEmpty) {
      problems.add(
        'dartvel.hosts has no primary host. Exactly one entry must have no mount (or mount: /).',
      );
    }
    if (primaries.length > 1) {
      problems.add(
        'dartvel.hosts has ${primaries.length} primary hosts (${primaries.map((DVHostEntry e) => e.pattern).join(', ')}). Exactly one entry may have no mount.',
      );
    }
    final Set<String> mounts = <String>{};
    for (final DVHostEntry e in entries) {
      if (!e.isPrimary && !mounts.add(e.mount)) {
        problems.add('dartvel.hosts: two hosts share the mount ${e.mount}.');
      }
    }
    return (
      hosts: problems.isEmpty
          ? DVHosts(List<DVHostEntry>.unmodifiable(entries), redirectHosts: List<DVHostRedirect>.unmodifiable(redirectHosts))
          : none,
      problems: problems,
    );
  }

  /// The list the manifest carries.
  List<Object?> toJson() => <Object?>[
    for (final DVHostEntry e in entries) e.toJson(),
  ];

  /// What [toJson] wrote; empty for anything else.
  static DVHosts fromJson(Object? json) {
    if (json is! List) return none;
    return DVHosts(
      List<DVHostEntry>.unmodifiable(<DVHostEntry>[
        for (final Object? e in json)
          if (e is Map) DVHostEntry.fromJson(e),
      ]),
    );
  }

  /// The entry for [host], exact names before wildcards, or null for a host
  /// nothing declares. [host] is normalised first (case, port, trailing dot).
  DVHostMatch? match(String host) {
    final String? name = dvNormaliseHost(host);
    if (name == null) return null;
    for (final DVHostEntry e in entries) {
      if (!e.isWildcard && e.pattern == name) return DVHostMatch(e);
    }
    for (final DVHostEntry e in entries) {
      if (!e.isWildcard) continue;
      final String suffix = e.pattern.substring(1);
      if (!name.endsWith(suffix)) continue;
      final String label = name.substring(0, name.length - suffix.length);
      if (_isLabel(label)) return DVHostMatch(e, label: label);
    }
    return null;
  }

  /// [match], or the primary host: an unknown host -- a health check, a
  /// bare IP -- is served as the primary.
  DVHostMatch matchOrPrimary(String? host) =>
      (host == null ? null : match(host)) ?? primaryMatch;

  /// The host that owns [internalPath]: the entry with the longest mount
  /// containing it, the primary host when none does.
  DVHostMatch owner(String internalPath) {
    final List<String> path = _segments(internalPath);
    DVHostMatch? best;
    int bestLength = -1;
    bool bestLiteral = false;
    for (final DVHostEntry e in entries) {
      if (e.isPrimary) continue;
      final List<String> mount = _segments(e.mount);
      if (mount.length > path.length) continue;
      String? label;
      bool fits = true;
      for (int i = 0; i < mount.length; i++) {
        if (mount[i] == '{label}') {
          if (!_isLabel(path[i])) {
            fits = false;
            break;
          }
          label = path[i];
        } else if (mount[i] != path[i]) {
          fits = false;
          break;
        }
      }
      if (!fits) continue;
      final bool literal = label == null;
      if (mount.length > bestLength ||
          (mount.length == bestLength && literal && !bestLiteral)) {
        best = DVHostMatch(e, label: label);
        bestLength = mount.length;
        bestLiteral = literal;
      }
    }
    return best ?? primaryMatch;
  }

  /// The entry that owns a route [pattern] such as `/apps/:id`, a parameter
  /// segment standing for any label. Null when there are no hosts.
  DVHostEntry? ownerOfPattern(String pattern) {
    if (isEmpty) return null;
    final String probe = _segments(pattern)
        .map((String s) => s.startsWith(':') ? 'x' : s)
        .join('/');
    return owner('/$probe').entry;
  }

  /// [internalPath] as an absolute URL on the host that owns it, with
  /// [query] when there is one. The root of a host is written as its origin
  /// with no trailing slash, as every canonical and sitemap URL Dartvel
  /// writes is; with a query it is `origin/?query`.
  String publicUrl(String internalPath, {String? query}) {
    final DVHostMatch m = owner(internalPath);
    final String path = m.hostPath(internalPath) ?? internalPath;
    final String trimmed = path.replaceAll(RegExp(r'/+$'), '');
    final String q = query == null || query.isEmpty ? '' : '?$query';
    if (trimmed.isEmpty) return q.isEmpty ? m.origin : '${m.origin}/$q';
    return '${m.origin}$trimmed$q';
  }

  /// Where a link to the internal [location] (a path, with any query and
  /// fragment) points when it is followed on [from]: a path on that host,
  /// its mount stripped, when it owns the route; the route's public URL on
  /// the host that does otherwise.
  ///
  /// The one rule for every link Dartvel writes, in the served document and
  /// in the running app. A mounted host shows only its mount, so a path left
  /// relative there for a route outside it names a page that host does not
  /// have.
  String linkFrom(DVHostMatch from, String location) {
    final int at = location.indexOf(RegExp('[?#]'));
    final String path = at < 0 ? location : location.substring(0, at);
    final String rest = at < 0 ? '' : location.substring(at);
    final DVHostMatch owningHost = owner(path);
    if (owningHost.origin == from.origin) return '${from.hostPath(path) ?? path}$rest';
    final int hash = rest.indexOf('#');
    final String query = hash < 0 ? rest : rest.substring(0, hash);
    final String fragment = hash < 0 ? '' : rest.substring(hash);
    return '${publicUrl(path, query: query.isEmpty ? null : query.substring(1))}$fragment';
  }
}

/// A host matched to its entry, with the label a wildcard matched.
final class const DVHostMatch(final DVHostEntry entry, {final String? label}) {
  /// The host's public origin, label substituted.
  String get origin =>
      _origin(_substitute(entry.siteUrl)) ?? _substitute(entry.siteUrl);

  /// The host's mount, label substituted: `/` for the primary host.
  String get mount => _substitute(entry.mount);

  /// The route a path on this host shows: `/` is the mount, `/x` is
  /// mount + `/x`.
  String internalPath(String hostPath) {
    final String path = hostPath.isEmpty
        ? '/'
        : (hostPath.startsWith('/') ? hostPath : '/$hostPath');
    final String m = mount;
    if (m == '/') return path;
    return path == '/' ? m : '$m$path';
  }

  /// The path on this host that shows [internalPath], or null when it is
  /// outside this host's mount.
  String? hostPath(String internalPath) {
    final String m = mount;
    if (m == '/') return internalPath.isEmpty ? '/' : internalPath;
    if (internalPath == m || internalPath == '$m/') return '/';
    if (internalPath.startsWith('$m/')) return internalPath.substring(m.length);
    return null;
  }

  /// Whether [internalPath] is this host's mount or below it.
  bool covers(String internalPath) => hostPath(internalPath) != null;

  /// Whether any of the route [patterns] lies under this host's mount. The
  /// primary host always serves. A wildcard label nothing is published for
  /// serves nothing, so its robots.txt and sitemap are not found.
  bool servesAnyOf(Iterable<String> patterns) {
    if (entry.isPrimary) return true;
    final List<String> m = _segments(mount);
    for (final String pattern in patterns) {
      final List<String> p = _segments(pattern);
      if (p.length < m.length) continue;
      bool fits = true;
      for (int i = 0; i < m.length; i++) {
        if (p[i] != m[i] && !p[i].startsWith(':')) {
          fits = false;
          break;
        }
      }
      if (fits) return true;
    }
    return false;
  }

  String _substitute(String text) =>
      label == null ? text : text.replaceAll('{label}', label!);
}

/// A request on one of the [hosts], decided: the route it means, the host
/// that owns that route, and where to send it when that is another host.
///
/// The web-server binary and `dartvel dev --release` both serve a request
/// through this, so the two answer alike.
final class const DVHostedRequest({
  required final DVHosts hosts,
  required final DVHostMatch requested,
  required final DVHostMatch owner,
  required final String path,
  final String? redirect,
}) {
  /// The path the page is rendered at: its path on its owner's host.
  String get pagePath => owner.hostPath(path) ?? path;

  /// The site the page is rendered on: its owner's origin, so its canonical
  /// link and og:url are its public URL.
  String get siteUrl => owner.origin;

  /// The owner's own site name and description, when it declares them. They
  /// stand in for `dartvel.seo`'s, never for a page's own.
  String? get siteName => owner.entry.name;
  String? get description => owner.entry.description;

  /// [internalPath] as a public URL, on whichever host owns it.
  String publicUrl(String internalPath, {String? query}) =>
      hosts.publicUrl(internalPath, query: query);

  /// [html], a page about to be answered on the host asked, with every
  /// anchor that names a route by its path pointing where that route is
  /// ([DVHosts.linkFrom]).
  ///
  /// The build reads each page once, on the primary host, so the document it
  /// captured links a primary route by its path. Served as it is on a mounted
  /// host, `/about` is that host's `/about`, which is not a page: the link
  /// has to say `https://example.com/about`. Only anchors are touched, and
  /// only paths [isRoute] says are routes: a file every host serves, a
  /// fragment and an address that is already a URL are left as written.
  /// The same string when nothing changes.
  String withLinks(
    String html, {
    required bool Function(String internalPath) isRoute,
  }) {
    if (!html.contains('<a ')) return html;
    bool changed = false;
    final String linked = html.replaceAllMapped(_anchorPath, (Match anchor) {
      final String href = anchor[2]!;
      final int at = href.indexOf(RegExp('[?#]'));
      final String path = at < 0 ? href : href.substring(0, at);
      if (!isRoute(path == '/' ? path : path.replaceAll(RegExp(r'/+$'), ''))) {
        return anchor[0]!;
      }
      final String link = hosts.linkFrom(requested, href);
      if (link == href) return anchor[0]!;
      changed = true;
      return '${anchor[1]}$link"';
    });
    return changed ? linked : html;
  }
}

/// An anchor's opening tag up to a double-quoted href that is a path on this
/// origin (`/x`, never `//host`).
final RegExp _anchorPath = RegExp(r'(<a\s(?:[^>]*?\s)?href=")(/(?!/)[^"]*)"');

/// [rawPath], asked for on [host], against [hosts].
///
/// The host is matched (an unknown one is the primary), the path mapped
/// through its mount and trimmed of trailing slashes as an unhosted request
/// is. When [isRoute] says that path is a route and another host owns it,
/// [DVHostedRequest.redirect] is that route's public URL, [query] kept. A
/// path no route serves is never redirected: it is not found where it was
/// asked.
DVHostedRequest dvHostedRequest(
  DVHosts hosts, {
  required String? host,
  required String rawPath,
  String? query,
  required bool Function(String internalPath) isRoute,
}) {
  final DVHostMatch requested = hosts.matchOrPrimary(host);
  final String mapped = requested.internalPath(rawPath);
  final String path = mapped == '/'
      ? '/'
      : mapped.replaceAll(RegExp(r'/+$'), '');
  final DVHostMatch owner = hosts.owner(path);
  final bool elsewhere = owner.origin != requested.origin && isRoute(path);
  return DVHostedRequest(
    hosts: hosts,
    requested: requested,
    owner: owner,
    path: path,
    redirect: elsewhere ? hosts.publicUrl(path, query: query) : null,
  );
}

/// A per-host `/robots.txt` or `/sitemap.xml`: its status, type and body.
typedef DVHostSiteFile = ({int status, String contentType, String body});

/// `/robots.txt` or `/sitemap.xml` on [host], or null when [path] is
/// neither or the build wrote no such file.
///
/// [robots] and [sitemap] are what the build wrote, or null. The sitemap
/// lists every page's public URL; each host is answered with the entries on
/// its own origin and a robots.txt naming its own sitemap. A host that
/// serves none of the route [patterns] -- a wildcard label nothing is
/// published under -- is answered 404 for both. Decided from [hosts], which
/// the caller parsed from the manifest, never from the files' text.
DVHostSiteFile? dvHostSiteFileFor(
  DVHosts hosts, {
  required String? host,
  required String path,
  required Iterable<String> patterns,
  required String? robots,
  required String? sitemap,
}) {
  if (hosts.isEmpty) return null;
  if (path != '/robots.txt' && path != '/sitemap.xml') return null;
  if ((path == '/robots.txt' ? robots : sitemap) == null) return null;
  final DVHostMatch match = hosts.matchOrPrimary(host);
  if (!match.servesAnyOf(patterns)) {
    return (status: 404, contentType: 'text/plain; charset=utf-8', body: 'Not found');
  }
  if (path == '/robots.txt') {
    return (
      status: 200,
      contentType: 'text/plain; charset=utf-8',
      body: dvRobotsTxt(siteUrl: match.origin, sitemap: sitemap != null),
    );
  }
  return (
    status: 200,
    contentType: 'application/xml; charset=utf-8',
    body: dvSitemapForOrigin(sitemap!, match.origin),
  );
}

/// [raw] as a host name: lowercase, with no port and no trailing dot, the
/// brackets taken off an IPv6 literal. Null for an empty or non-ASCII host
/// (internationalised names arrive as punycode; anything else is refused
/// rather than mapped).
String? dvNormaliseHost(String? raw) {
  if (raw == null) return null;
  String host = raw.trim().toLowerCase();
  if (host.isEmpty || !_ascii(host)) return null;
  if (host.startsWith('[')) {
    final int close = host.indexOf(']');
    if (close < 0) return null;
    host = host.substring(1, close);
  } else {
    final int colon = host.indexOf(':');
    // One colon is host:port. More than one unbracketed is a bare IPv6
    // address, which has no port to strip.
    if (colon >= 0 && host.indexOf(':', colon + 1) < 0) {
      host = host.substring(0, colon);
    }
  }
  while (host.endsWith('.')) {
    host = host.substring(0, host.length - 1);
  }
  return host.isEmpty ? null : host;
}

/// The host a request was made for: `X-Forwarded-Host` when the peer is a
/// proxy the application trusts (`dartvel.server.trustedProxies`, decided by
/// `DVClientAddress`), the `Host` header otherwise. Of several forwarded
/// entries the last is used: it is the one the trusted peer wrote, and
/// anything to its left came from further away. Normalised by
/// [dvNormaliseHost].
String? dvEffectiveHost({
  required String? host,
  String? forwardedHost,
  required bool peerIsTrustedProxy,
}) {
  if (peerIsTrustedProxy &&
      forwardedHost != null &&
      forwardedHost.trim().isNotEmpty) {
    final String last = forwardedHost.split(',').last;
    final String? forwarded = dvNormaliseHost(last);
    if (forwarded != null) return forwarded;
  }
  return dvNormaliseHost(host);
}

/// A robots.txt allowing everything and naming [siteUrl]'s sitemap when
/// [sitemap]. What the build writes, and what the server answers per host.
String dvRobotsTxt({required String siteUrl, bool sitemap = true}) {
  final String base = siteUrl.replaceAll(RegExp(r'/+$'), '');
  const String head =
      'User-agent: *\n'
      'Allow: /\n';
  if (!sitemap) return head;
  return '$head'
      '\n'
      'Sitemap: $base/sitemap.xml\n';
}

/// [sitemap] with only the `<url>` entries whose location is on [origin].
/// The build writes one sitemap of every page's public URL; each host is
/// answered with its own part of it.
String dvSitemapForOrigin(String sitemap, String origin) =>
    sitemap.replaceAllMapped(
      RegExp(r'[ \t]*<url>.*?</url>[ \t]*\r?\n?', dotAll: true),
      (Match m) {
        final String? loc = RegExp(
          r'<loc>(.*?)</loc>',
          dotAll: true,
        ).firstMatch(m[0]!)?.group(1);
        if (loc == null) return '';
        final String url = loc.trim().replaceAll('&amp;', '&');
        return _origin(url, allowPath: true) == origin ? m[0]! : '';
      },
    );

/// Whether [sitemap] lists any `<url>`.
bool dvSitemapHasUrls(String sitemap) => sitemap.contains('<url>');

bool _ascii(String s) => s.codeUnits.every((int u) => u < 0x80);

final RegExp _labelPattern = RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$');

/// A lowercase DNS label.
bool _isLabel(String s) => _labelPattern.hasMatch(s);

List<String> _segments(String path) =>
    path.split('/').where((String s) => s.isNotEmpty).toList();

/// `scheme://host[:port]` of an http(s) [url], or null. With [allowPath]
/// false the URL must be an origin alone (a trailing `/` allowed).
String? _origin(String url, {bool allowPath = false}) {
  final Uri? uri = Uri.tryParse(url);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    return null;
  }
  if (!allowPath &&
      ((uri.path.isNotEmpty && uri.path != '/') ||
          uri.hasQuery ||
          uri.hasFragment ||
          uri.userInfo.isNotEmpty)) {
    return null;
  }
  return uri.origin;
}
