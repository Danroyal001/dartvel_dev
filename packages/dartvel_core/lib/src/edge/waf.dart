/// Typed request-filtering rules: written once, reviewable in a diff, run by
/// a platform firewall where an adapter can push them there and as middleware
/// everywhere.
///
/// Dartvel is not a firewall vendor. The rules and the diagnostics are
/// Dartvel's; where a CDN or cloud WAF exists, an adapter installs the same
/// rules on it.
library dartvel_core.edge.waf;

import '../http/client_address.dart';
import '../middleware/middleware.dart';
import '../observability/observability.dart';
import 'request_parts.dart';

/// Resolves the country a request came from, as an ISO 3166 alpha-2 code, or
/// null when it cannot tell.
typedef DVWafCountryResolver = String? Function(Object? request);

/// What a matching rule does.
enum DVWafAction {
  /// Refuse the request (`DV-EDGE-003`).
  refuse,

  /// Let the request through without consulting later rules: an exception
  /// carved out of a broader rule listed after it.
  allow,
}

/// Where a rule applies.
///
/// A request whose country is unknown is outside every [within] list and
/// therefore inside every [notIn] one: an allow-list fails closed.
class DVWafSource {
  const DVWafSource.anywhere()
      : _countries = null,
        _inside = true;

  /// Requests from one of [countries].
  const DVWafSource.within(List<String> countries)
      : _countries = countries,
        _inside = true;

  /// Requests from anywhere but [countries], including from nowhere known.
  const DVWafSource.notIn(List<String> countries)
      : _countries = countries,
        _inside = false;

  final List<String>? _countries;
  final bool _inside;

  bool get isAnywhere => _countries == null;

  bool matches(String? country) {
    final countries = _countries;
    if (countries == null) return true;
    final code = country?.trim().toUpperCase();
    final listed = code != null &&
        code.isNotEmpty &&
        countries.any((listed) => listed.toUpperCase() == code);
    return _inside ? listed : !listed;
  }
}

/// One request-filtering rule.
class DVWafRule {
  const DVWafRule({
    required this.name,
    this.paths = const <String>['/**'],
    this.methods = const <String>[],
    this.from = const DVWafSource.anywhere(),
    this.action = DVWafAction.refuse,
  });

  /// Unique within a rule set; findings and refusals name the rule by it.
  final String name;

  /// Path globs: `*` is one segment, `**` any number of them, including none.
  final List<String> paths;

  /// Methods the rule applies to; empty is every method.
  final List<String> methods;

  final DVWafSource from;
  final DVWafAction action;

  /// Whether the rule applies to every request there is.
  bool get matchesEverything =>
      methods.isEmpty &&
      from.isAnywhere &&
      paths.any((path) => _segments(path).every((part) => part == '**'));

  bool matches({
    required String method,
    required String path,
    String? country,
  }) {
    if (methods.isNotEmpty &&
        !methods.any((m) => m.toUpperCase() == method.toUpperCase())) {
      return false;
    }
    if (!from.matches(country)) return false;
    final segments = _segments(_normalisePath(path));
    return paths.any((glob) => _globMatches(_segments(glob), 0, segments, 0));
  }
}

/// The rule that decided a request, if any did.
class DVWafDecision {
  const DVWafDecision._(this.rule);

  final DVWafRule? rule;

  bool get refused => rule?.action == DVWafAction.refuse;
}

/// A rule `dartvel analyze` reports (`DV-EDGE-006`).
class DVWafFinding {
  const DVWafFinding(this.rule, this.reason);

  final String rule;
  final String reason;

  String get code => 'DV-EDGE-006';

  @override
  String toString() => '$code: WAF rule "$rule" $reason.';
}

/// Installs rules on a platform firewall -- a CDN, a load balancer, a cloud
/// WAF -- so they run before a request reaches the application.
abstract interface class DVWafAdapter {
  /// For logs: `cloudflare`, `cloudfront`, `recording`.
  String get name;

  Future<void> install(List<DVWafRule> rules);
}

/// An adapter that installs nowhere and remembers what it was given. For
/// tests, and for checking what a deploy would push.
class DVRecordingWafAdapter implements DVWafAdapter {
  DVRecordingWafAdapter({this.failWith});

  /// Thrown from [install], to exercise a firewall that refuses the push.
  final Object? failWith;

  List<DVWafRule> installed = const <DVWafRule>[];

  @override
  String get name => 'recording';

  @override
  Future<void> install(List<DVWafRule> rules) async {
    final failure = failWith;
    if (failure != null) throw failure;
    installed = List<DVWafRule>.unmodifiable(rules);
  }
}

/// A rule set, the middleware that enforces it, and the adapter that pushes
/// it to a platform firewall.
///
/// The middleware runs whether or not an adapter installed the rules: one
/// that failed to push, or a request that reached the origin directly, is
/// still refused.
class DVWaf {
  DVWaf(
    List<DVWafRule> rules, {
    DVWafCountryResolver? countryOf,
    this.adapter,
    DateTime Function()? clock,
  })  : rules = List<DVWafRule>.unmodifiable(rules),
        _countryOf = countryOf,
        _clock = clock ?? DateTime.now {
    final names = <String>{};
    for (final rule in rules) {
      if (!names.add(rule.name)) {
        throw ArgumentError.value(
          rule.name,
          'rules',
          'names two rules; a refusal and a finding must say which one',
        );
      }
    }
    _since = _clock();
  }

  /// How long a rule may match nothing before it is reported.
  static const Duration staleAfter = Duration(days: 90);

  final List<DVWafRule> rules;
  final DVWafAdapter? adapter;
  final DVWafCountryResolver? _countryOf;
  final DateTime Function() _clock;
  late final DateTime _since;
  final Map<String, DateTime> _lastMatched = <String, DateTime>{};

  /// When each rule last matched a request in this process.
  Map<String, DateTime> get lastMatched =>
      Map<String, DateTime>.unmodifiable(_lastMatched);

  /// Reads the country from a header a CDN sets, such as `cf-ipcountry`,
  /// when the request came straight from a trusted proxy.
  ///
  /// Opt-in by name, and believed only from a peer [DVClientAddress.current]
  /// trusts: a header is only as trustworthy as the proxy that overwrites it,
  /// and a client that reaches the origin directly can send any header it
  /// likes. From anywhere else the country is unknown, which is outside every
  /// allow-list.
  static DVWafCountryResolver countryHeader(String header) => (request) =>
      DVClientAddress.current.peerIsTrusted(request)
          ? dvEdgeHeader(request, header)
          : null;

  /// Pushes the rules to [adapter]. A failure is thrown, not swallowed; the
  /// middleware keeps enforcing either way.
  Future<void> deploy() async {
    await adapter?.install(rules);
  }

  /// The first rule that matches, which decides.
  DVWafDecision decide({
    required String method,
    required String path,
    String? country,
  }) {
    for (final rule in rules) {
      if (rule.matches(method: method, path: path, country: country)) {
        _lastMatched[rule.name] = _clock();
        return DVWafDecision._(rule);
      }
    }
    return const DVWafDecision._(null);
  }

  Middleware middleware() => (request, context) {
        String? country;
        try {
          country = _countryOf?.call(request);
        } catch (error) {
          DVObservability.log(
            'The WAF could not resolve the request country; it is unknown.',
            level: DVLogLevel.warn,
            error: error,
          );
        }
        final decision = decide(
          method: dvEdgeMethod(request),
          path: dvEdgePath(request),
          country: country,
        );
        final rule = decision.rule;
        if (rule == null || !decision.refused) return;
        context.abort();
        context.data['wafError'] = 'Forbidden';
        context.data['wafRule'] = rule.name;
        context.data['diagnostic'] = 'DV-EDGE-003';
        DVObservability.log(
          'WAF rule "${rule.name}" refused the request.',
          code: 'DV-EDGE-003',
        );
      };

  /// Rules that match every request, and rules that have matched nothing for
  /// [staleAfter]: a rule nobody can explain is a rule nobody dares delete.
  ///
  /// Matches are remembered for the life of this [DVWaf]; a rule that has not
  /// matched is measured from when it was constructed.
  List<DVWafFinding> lint() {
    final now = _clock();
    return <DVWafFinding>[
      for (final rule in rules)
        if (rule.matchesEverything)
          DVWafFinding(rule.name, 'matches every request')
        else if (now.difference(_lastMatched[rule.name] ?? _since) >
            staleAfter)
          DVWafFinding(
            rule.name,
            'has matched nothing for ${staleAfter.inDays} days',
          ),
    ];
  }
}

List<String> _segments(String path) => <String>[
      for (final segment in path.split('/'))
        if (segment.isNotEmpty) segment,
    ];

/// The path a router serves for [raw]: query and fragment dropped, decoded
/// once, empty and dot segments resolved. Matching the raw text instead lets
/// `//admin`, `/%61dmin` and `/x/../admin` past a rule for `/admin/**`.
String _normalisePath(String raw) {
  var path = raw;
  final cut = path.indexOf(RegExp('[?#]'));
  if (cut >= 0) path = path.substring(0, cut);
  try {
    path = Uri.decodeComponent(path);
  } catch (_) {
    // Malformed percent-encoding: match what was sent.
  }
  final resolved = <String>[];
  for (final segment in path.replaceAll(r'\', '/').split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (resolved.isNotEmpty) resolved.removeLast();
      continue;
    }
    resolved.add(segment);
  }
  return '/${resolved.join('/')}';
}

bool _globMatches(List<String> glob, int g, List<String> path, int p) {
  if (g == glob.length) return p == path.length;
  final part = glob[g];
  if (part == '**') {
    for (var next = p; next <= path.length; next++) {
      if (_globMatches(glob, g + 1, path, next)) return true;
    }
    return false;
  }
  if (p == path.length || !_segmentMatches(part, path[p])) return false;
  return _globMatches(glob, g + 1, path, p + 1);
}

bool _segmentMatches(String glob, String segment) {
  if (glob == '*') return true;
  if (!glob.contains('*')) return glob == segment;
  final pattern = glob.split('*').map(RegExp.escape).join('[^/]*');
  return RegExp('^$pattern\$').hasMatch(segment);
}
