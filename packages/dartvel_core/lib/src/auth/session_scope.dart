/// How far a browser session reaches across an application's hosts.
///
/// An application whose `dartvel.hosts` serves several hosts under one
/// registrable domain -- `example.com`, `tools.example.com`,
/// `*.tools.example.com` -- is one application, and a person signed in on one
/// of them is signed in on all of them. A `__Host-` cookie cannot do that: a
/// browser locks it to the exact host that set it. So when the declared hosts
/// share a registrable domain the session cookie is `__Secure-dv_session`
/// with `Domain=<that domain>`, still `HttpOnly`, `Secure` and
/// `SameSite=Lax`; an application with one host keeps `__Host-` exactly as
/// before.
///
/// What goes wrong here goes wrong silently, so each guard says where it is:
///
/// * the domain is the hosts' registrable domain by the Public Suffix List,
///   never "the last two labels", and a public suffix is refused -- a browser
///   drops such a cookie without a word, and one that did not would hand the
///   session to strangers;
/// * only a host the application declares, under that domain, is given the
///   domain cookie. A redirecting host, a host on another registrable domain
///   and a host nothing declares keep a host-only cookie of their own;
/// * a state-changing request whose `Origin` is not one of the application's
///   own hosts (or an origin `dartvel.server.cors` names) is refused, so a
///   sibling somebody else runs under the same domain cannot act as the
///   application;
/// * `dartvel.auth.sessionScope: host` keeps per-host cookies, and
///   `dartvel.auth.sessionDomain` names the domain explicitly; both are
///   checked when the backend is generated and again when it starts.
library dartvel_core.auth.session_scope;

import '../http/client_address.dart';
import '../http/wintercg.dart';
import '../web/host_routing.dart';
import '../web/public_suffix.dart';
import 'sessions.dart' show DVSessionConfigError;

/// A [DVSessionScope] read from `dartvel.hosts` and `dartvel.auth`, and the
/// problems found reading it. A build with any refuses to continue.
typedef DVSessionScopeResolution = ({
  DVSessionScope scope,
  List<String> problems,
});

/// Which hosts share one browser session.
final class DVSessionScope {
  /// Every host keeps a host-only `__Host-` cookie. [hosts] are the
  /// application's own serving hosts, when it declares any: a
  /// state-changing request from anywhere else is refused.
  const DVSessionScope.host({this.hosts = const <String>[]}) : domain = null;

  /// The session spans every one of [hosts] under [domain].
  const DVSessionScope.site({required String this.domain, required this.hosts});

  /// The registrable domain (or a parent of every covered host under it) the
  /// session cookie is set for, or null for host-only cookies.
  final String? domain;

  /// The application's own serving hosts: exact names and `*.` patterns
  /// from `dartvel.hosts`, redirecting hosts left out.
  final List<String> hosts;

  /// The values `dartvel.auth.sessionScope` takes.
  static const String siteScope = 'site';
  static const String hostScope = 'host';

  /// Whether a request on [host] gets the domain cookie: the application
  /// declares it, and it is [domain] or below it.
  bool covers(String? host) {
    final String? spanned = domain;
    if (spanned == null || host == null) return false;
    final String? name = dvNormaliseHost(host);
    if (name == null) return false;
    if (name != spanned && !name.endsWith('.$spanned')) return false;
    return _declared(name);
  }

  bool _declared(String name) =>
      hosts.any((String pattern) => _matches(pattern, name));

  static bool _matches(String pattern, String name) {
    if (!pattern.startsWith('*.')) return pattern == name;
    final String suffix = pattern.substring(1);
    if (!name.endsWith(suffix)) return false;
    final String label = name.substring(0, name.length - suffix.length);
    return label.isNotEmpty && !label.contains('.');
  }

  /// Whether a state-changing request carrying [origin], made to [host], is
  /// the application's own.
  ///
  /// With no declared hosts nothing is checked here, as before: the CSRF
  /// token is the guard. Otherwise the origin must be https (http only on
  /// this machine) on one of [hosts], the host the request was made to, or
  /// one of [alsoAllowed] -- the origins `dartvel.server.cors` names. The
  /// port is not compared: a browser sends a host's cookies to every port.
  /// A request with no `Origin` -- a native client, a server -- is judged by
  /// its CSRF token and credentials alone. `Origin: null` is refused.
  bool allowsOrigin(
    String? origin, {
    String? host,
    Iterable<String> alsoAllowed = const <String>[],
  }) {
    if (hosts.isEmpty || origin == null) return true;
    final String written = origin.trim().toLowerCase();
    for (final String allowed in alsoAllowed) {
      if (_bareOrigin(allowed) == _bareOrigin(written)) return true;
    }
    final Uri? uri = Uri.tryParse(written);
    if (uri == null ||
        !(uri.scheme == 'https' || uri.scheme == 'http') ||
        uri.host.isEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      return false;
    }
    final String originHost = uri.host;
    final bool loopback = originHost == 'localhost' ||
        originHost == '127.0.0.1' ||
        originHost == '::1';
    if (uri.scheme == 'http' && !loopback) return false;
    final String? requested = dvNormaliseHost(host);
    if (requested != null && requested == originHost) return true;
    return _declared(originHost);
  }

  static String _bareOrigin(String origin) =>
      origin.trim().toLowerCase().replaceAll(RegExp(r'/+$'), '');

  /// Throws [DVSessionConfigError] when [domain] is a public suffix, not a
  /// domain at all, or covers none of [hosts]: the start-time half of what
  /// [resolve] reports at build time.
  void validate() {
    final String? spanned = domain;
    if (spanned == null) return;
    final String? reason = _domainProblem(spanned);
    if (reason != null) {
      throw DVSessionConfigError(
          setting: 'sessionDomain', value: spanned, reason: reason);
    }
    if (!hosts.any((String pattern) => _under(_base(pattern), spanned))) {
      throw DVSessionConfigError(
        setting: 'sessionDomain',
        value: spanned,
        reason: 'none of the application\'s hosts (${hosts.join(', ')}) is '
            'under it, so the cookie would reach no host it serves',
      );
    }
  }

  static String _base(String pattern) =>
      pattern.startsWith('*.') ? pattern.substring(2) : pattern;

  static bool _under(String name, String domain) =>
      name == domain || name.endsWith('.$domain');

  static String? _domainProblem(String domain) {
    if (dvIsPublicSuffix(domain)) {
      return 'it is a public suffix, under which unrelated parties register: '
          'a browser refuses a cookie for it, and one that accepted it would '
          'send the session to every site under it';
    }
    if (dvRegistrableDomain(domain) == null) {
      return 'it is not a registrable domain name (an address, localhost or '
          'something that is not a host name cannot share a cookie)';
    }
    return null;
  }

  /// The scope `dartvel.hosts` and `dartvel.auth` describe.
  ///
  /// [auth] is the `dartvel.auth` map, or null. Without `sessionScope` or
  /// `sessionDomain`, hosts sharing the primary host's registrable domain
  /// share the session when there are two or more of them (or a wildcard);
  /// the rest keep host-only cookies. Every problem is reported.
  static DVSessionScopeResolution resolve({
    required DVHosts hosts,
    Object? auth,
  }) {
    final List<String> problems = <String>[];
    final List<String> serving = <String>[
      for (final DVHostEntry entry in hosts.entries) entry.pattern,
    ];
    final DVSessionScope hostOnly = DVSessionScope.host(hosts: serving);
    if (auth != null && auth is! Map) {
      problems.add('dartvel.auth must be a map, not "$auth".');
      return (scope: hostOnly, problems: problems);
    }
    final Object? scopeRaw = auth is Map ? auth['sessionScope'] : null;
    final Object? domainRaw = auth is Map ? auth['sessionDomain'] : null;
    final String scope = scopeRaw == null ? siteScope : '$scopeRaw'.trim();
    if (scope != siteScope && scope != hostScope) {
      problems.add('dartvel.auth.sessionScope must be "$siteScope" (the '
          'default: one session across the application\'s hosts on one '
          'registrable domain) or "$hostScope" (a session per host), not '
          '"$scopeRaw".');
      return (scope: hostOnly, problems: problems);
    }
    if (domainRaw != null && (domainRaw is! String || domainRaw.trim().isEmpty)) {
      problems.add('dartvel.auth.sessionDomain must be a domain name such as '
          'example.com, not "$domainRaw".');
      return (scope: hostOnly, problems: problems);
    }
    final String? named =
        domainRaw == null ? null : dvNormaliseHost(domainRaw as String);
    if (scope == hostScope) {
      if (domainRaw != null) {
        problems.add('dartvel.auth.sessionDomain cannot be set with '
            'sessionScope: host, which keeps every session on the host that '
            'set it. Remove one of the two.');
      }
      return (scope: hostOnly, problems: problems);
    }
    if (named != null) {
      if (hosts.isEmpty) {
        problems.add('dartvel.auth.sessionDomain is "$named" and dartvel.hosts '
            'declares no hosts for the session to span. Declare them under '
            'dartvel.hosts, or remove sessionDomain.');
        return (scope: hostOnly, problems: problems);
      }
      final String? reason = _domainProblem(named);
      if (reason != null) {
        problems.add('dartvel.auth.sessionDomain "$named" is refused: '
            '$reason. Name the registrable domain your hosts share, such as '
            '${dvRegistrableDomain(_base(serving.first)) ?? 'example.com'}.');
        return (scope: hostOnly, problems: problems);
      }
      for (final String pattern in serving) {
        if (!_under(_base(pattern), named)) {
          problems.add('dartvel.auth.sessionDomain "$named" is refused: the '
              'host "$pattern" in dartvel.hosts is not under it, so it would '
              'be signed out of a session its sibling hosts share. Name a '
              'parent of every host, or use sessionScope: host.');
        }
      }
      if (problems.isNotEmpty) return (scope: hostOnly, problems: problems);
      return (
        scope: DVSessionScope.site(domain: named, hosts: serving),
        problems: problems,
      );
    }
    if (hosts.isEmpty) return (scope: const DVSessionScope.host(), problems: problems);
    final String? primary = _registrable(hosts.primary.pattern);
    if (primary == null) return (scope: hostOnly, problems: problems);
    final List<String> members = <String>[
      for (final String pattern in serving)
        if (_registrable(pattern) == primary) pattern,
    ];
    final bool shared = members.length > 1 ||
        members.any((String pattern) => pattern.startsWith('*.'));
    return (
      scope: shared
          ? DVSessionScope.site(domain: primary, hosts: serving)
          : hostOnly,
      problems: problems,
    );
  }

  /// The registrable domain every host [pattern] matches shares, or null --
  /// for a wildcard directly under a public suffix each label is its own.
  static String? _registrable(String pattern) {
    if (!pattern.startsWith('*.')) return dvRegistrableDomain(pattern);
    final String probe = 'dv-probe.${pattern.substring(2)}';
    final String? registrable = dvRegistrableDomain(probe);
    return registrable == probe ? null : registrable;
  }

  /// The host [request] was made for: `X-Forwarded-Host` from a peer
  /// `dartvel.server.trustedProxies` trusts, `Host` otherwise.
  static String? requestHost(Request request) {
    final List<String> forwarded =
        request.headers.getAll('x-forwarded-host').toList();
    return dvEffectiveHost(
      host: request.headers.get('host') ?? request.url.host,
      forwardedHost: forwarded.isEmpty ? null : forwarded.join(','),
      peerIsTrustedProxy: DVClientAddress.current.peerIsTrusted(request),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        if (domain != null) 'domain': domain,
        'hosts': hosts,
      };

  @override
  String toString() => domain == null
      ? 'DVSessionScope.host(${hosts.join(', ')})'
      : 'DVSessionScope.site($domain: ${hosts.join(', ')})';
}
