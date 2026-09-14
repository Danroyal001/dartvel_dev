/// The capabilities a module can ask a parent for, and what a grant covers.
///
/// Module Distribution and Trust: a module mounted with no grants has no
/// capabilities. What needs a grant is the small set of surfaces that reach
/// past the module's own boundary -- named secrets, raw SQL, native bindings,
/// egress per domain, a filesystem root, and scheduled work in the parent's
/// scheduler.
///
/// The same shape is read in three places: the module's declaration
/// (`dartvel.module.capabilities`), the parent's grant
/// (`dartvel.modules.<id>.grant`), and the signed statement a publisher
/// attaches. Reading them with one parser is what lets them be compared.
///
/// Everything here fails closed. A value that cannot be read grants nothing
/// and says why: a grant that reads a typo as permission is worse than no
/// grant at all, because it looks like a decision somebody made.
library;

/// The capabilities, in the order the specification's table lists them.
const List<String> dvModuleCapabilityKinds = <String>[
  'secrets',
  'rawSql',
  'nativeBindings',
  'egress',
  'filesystem',
  'cron',
];

/// What a module uses, declares, or is granted.
class DVModuleCapabilities {
  const DVModuleCapabilities({
    this.secrets = const <String>{},
    this.rawSql = false,
    this.nativeBindings = false,
    this.egress = const <String>{},
    this.filesystem = const <String>{},
    this.cron = false,
  });

  /// No capabilities: what a module mounted with no grant has.
  static const DVModuleCapabilities none = DVModuleCapabilities();

  /// Secret keys, exactly as named. A grant lists keys, not the namespace.
  final Set<String> secrets;
  final bool rawSql;
  final bool nativeBindings;

  /// Hosts, lowercased. Exact: a grant for `stripe.com` is not a grant for
  /// `api.stripe.com`, and nothing is matched by suffix.
  final Set<String> egress;

  /// Named roots, not the disk.
  final Set<String> filesystem;
  final bool cron;

  bool get isEmpty =>
      secrets.isEmpty &&
      !rawSql &&
      !nativeBindings &&
      egress.isEmpty &&
      filesystem.isEmpty &&
      !cron;

  /// The kinds that carry anything, in table order: the lockfile's form.
  List<String> get kinds => <String>[
    if (secrets.isNotEmpty) 'secrets',
    if (rawSql) 'rawSql',
    if (nativeBindings) 'nativeBindings',
    if (egress.isNotEmpty) 'egress',
    if (filesystem.isNotEmpty) 'filesystem',
    if (cron) 'cron',
  ];

  /// One line per grantable thing, as a finding names it.
  List<String> items() => <String>[
    for (final String s in _sorted(secrets)) 'secrets: $s',
    if (rawSql) 'rawSql',
    if (nativeBindings) 'nativeBindings',
    for (final String e in _sorted(egress)) 'egress: $e',
    for (final String f in _sorted(filesystem)) 'filesystem: $f',
    if (cron) 'cron',
  ];

  /// What this asks for that [granted] does not cover.
  ///
  /// Compared kind by kind and by exact value. Nothing is covered by prefix,
  /// suffix or case: each of those is a grant for something nobody wrote.
  List<String> missingFrom(DVModuleCapabilities granted) =>
      DVModuleCapabilities(
        secrets: secrets.difference(granted.secrets),
        rawSql: rawSql && !granted.rawSql,
        nativeBindings: nativeBindings && !granted.nativeBindings,
        egress: egress.difference(granted.egress),
        filesystem: filesystem.difference(granted.filesystem),
        cron: cron && !granted.cron,
      ).items();

  /// The canonical form: keys sorted, lists sorted, every key present.
  Map<String, Object?> toJson() => <String, Object?>{
    'cron': cron,
    'egress': _sorted(egress),
    'filesystem': _sorted(filesystem),
    'nativeBindings': nativeBindings,
    'rawSql': rawSql,
    'secrets': _sorted(secrets),
  };

  /// Reads [toJson]'s form. Throws [FormatException] on anything else, so a
  /// signed statement that does not parse is refused rather than read as
  /// asking for nothing.
  static DVModuleCapabilities fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('capabilities are not an object');
    }
    Set<String> strings(String key) {
      final Object? value = json[key];
      if (value is! List || value.any((Object? v) => v is! String)) {
        throw FormatException('capabilities.$key is not a list of strings');
      }
      return value.cast<String>().toSet();
    }

    bool flag(String key) {
      final Object? value = json[key];
      if (value is! bool) {
        throw FormatException('capabilities.$key is not true or false');
      }
      return value;
    }

    final Set<Object?> keys = json.keys.toSet();
    if (keys.length != dvModuleCapabilityKinds.length ||
        !dvModuleCapabilityKinds.every(keys.contains)) {
      throw const FormatException('capabilities carry unexpected keys');
    }
    return DVModuleCapabilities(
      secrets: strings('secrets'),
      rawSql: flag('rawSql'),
      nativeBindings: flag('nativeBindings'),
      egress: strings('egress'),
      filesystem: strings('filesystem'),
      cron: flag('cron'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DVModuleCapabilities && _same(items(), other.items());

  @override
  int get hashCode => Object.hashAll(items());

  @override
  String toString() => isEmpty ? 'no capabilities' : items().join(', ');
}

bool _same(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

List<String> _sorted(Set<String> values) => values.toList()..sort();

/// The capabilities read, and what could not be.
class DVCapabilityParse {
  const DVCapabilityParse(this.capabilities, this.problems);

  final DVModuleCapabilities capabilities;
  final List<String> problems;
}

final RegExp _host = RegExp(
  r'^(?=.{1,253}$)[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?'
  r'(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*$',
);

/// [raw] as a grantable host, or null when it is not one.
///
/// Lowercased because DNS is, and for no other reason: nothing is trimmed,
/// and a scheme, a path, a port or a wildcard makes it not a host. A wildcard
/// is `network: true` spelled longer.
String? dvNormaliseEgressDomain(String raw) {
  final String lower = raw.toLowerCase();
  return _host.hasMatch(lower) ? lower : null;
}

final RegExp _secretName = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
final RegExp _root = RegExp(r'^/?[^/\s*]+$');

/// Reads a capabilities map written at [where].
DVCapabilityParse dvParseModuleCapabilities(
  Object? raw, {
  required String where,
}) {
  if (raw == null) {
    return const DVCapabilityParse(DVModuleCapabilities.none, <String>[]);
  }
  final List<String> problems = <String>[];
  if (raw is! Map) {
    problems.add(
      '$where is "$raw". It is a map of capabilities -- secrets, '
      'rawSql, nativeBindings, egress, filesystem, cron -- so nothing is '
      'granted from it.',
    );
    return DVCapabilityParse(DVModuleCapabilities.none, problems);
  }

  final Set<String> secrets = <String>{};
  final Set<String> egress = <String>{};
  final Set<String> filesystem = <String>{};
  var rawSql = false;
  var nativeBindings = false;
  var cron = false;

  List<String>? list(String key, Object? value) {
    if (value is List) {
      return <String>[
        for (final Object? v in value)
          if (v is String)
            v
          else
            ...(() {
              problems.add('$where.$key has "$v", which is not a name.');
              return const <String>[];
            })(),
      ];
    }
    problems.add(
      '$where.$key is "$value". It is a list, as in [$value], '
      'even with one entry, so nothing is granted from it.',
    );
    return null;
  }

  bool flag(String key, Object? value) {
    if (value is bool) return value;
    problems.add(
      '$where.$key is "$value". It is true or false, and a value '
      'that is neither grants nothing.',
    );
    return false;
  }

  for (final MapEntry<Object?, Object?> entry in raw.entries) {
    final String key = '${entry.key}';
    final Object? value = entry.value;
    switch (key) {
      case 'secrets':
        for (final String name in list(key, value) ?? const <String>[]) {
          if (_secretName.hasMatch(name)) {
            secrets.add(name);
          } else {
            problems.add(
              '$where.secrets has "$name", which is not a secret '
              'name.',
            );
          }
        }
      case 'egress':
        for (final String domain in list(key, value) ?? const <String>[]) {
          final String? host = dvNormaliseEgressDomain(domain);
          if (host == null) {
            problems.add(
              '$where.egress has "$domain". Egress is granted per '
              'domain: a bare host such as api.stripe.com, with no scheme, '
              'path, port or wildcard.',
            );
          } else {
            egress.add(host);
          }
        }
      case 'filesystem':
        for (final String root in list(key, value) ?? const <String>[]) {
          if (_root.hasMatch(root) &&
              root != '.' &&
              root != '..' &&
              root != '/.' &&
              root != '/..') {
            filesystem.add(root);
          } else {
            problems.add(
              '$where.filesystem has "$root". A filesystem grant '
              'is one named root, such as uploads, not a path or the disk.',
            );
          }
        }
      case 'rawSql':
        rawSql = flag(key, value);
      case 'nativeBindings':
        nativeBindings = flag(key, value);
      case 'cron':
        cron = flag(key, value);
      case 'network':
        problems.add(
          '$where.network is not a capability. A module that can '
          'reach any host needs no other permission to leak what it reads, '
          'so egress is granted per domain: egress: [api.example.com].',
        );
      default:
        problems.add(
          '$where.$key is not a capability. The capabilities are '
          '${dvModuleCapabilityKinds.join(', ')}.',
        );
    }
  }

  return DVCapabilityParse(
    DVModuleCapabilities(
      secrets: secrets,
      rawSql: rawSql,
      nativeBindings: nativeBindings,
      egress: egress,
      filesystem: filesystem,
      cron: cron,
    ),
    problems,
  );
}
