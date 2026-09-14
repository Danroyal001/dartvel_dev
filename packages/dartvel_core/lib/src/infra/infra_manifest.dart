/// `dartvel.infra` in `pubspec.yaml`: the hosts an environment runs on and
/// what a provisioned host is declared to have.
///
/// Read strictly, like `dartvel.deploy`. A key that cannot be read is refused
/// rather than defaulted: a misspelt `instance: 2` that quietly became one
/// instance is a host provisioned to a manifest nobody wrote.
library;

/// How the provisioner reaches a host.
enum DVInfraAdapterKind {
  ssh('ssh'),
  container('container'),
  onprem('onprem');

  const DVInfraAdapterKind(this.configName);

  final String configName;
}

/// How to reach a host over SSH, and which key it must present.
///
/// Not in the specification's example, which has no way to say which host
/// key is the right one. Without that the first connection trusts whatever
/// answers, so the manifest names a known_hosts file checked in beside it and
/// nothing connects to a host that file does not pin.
final class DVInfraSsh {
  const DVInfraSsh({
    this.user = 'root',
    this.port = 22,
    this.knownHosts = 'infra/known_hosts',
  });

  final String user;
  final int port;

  /// Relative to the project root.
  final String knownHosts;
}

/// Certificates, and who the ACME account belongs to.
final class DVInfraTls {
  const DVInfraTls({required this.domains, required this.acmeEmail});

  final List<String> domains;
  final String acmeEmail;
}

/// The supervised services.
final class DVInfraServices {
  const DVInfraServices({
    this.backendInstances = 1,
    this.workerQueues = const <String>[],
    this.workerInstances = 0,
    this.cron,
  });

  final int backendInstances;
  final List<String> workerQueues;

  /// Per queue. Zero when no workers are declared.
  final int workerInstances;

  /// Null when the manifest does not say.
  final bool? cron;
}

/// `database.backup`.
final class DVInfraBackup {
  const DVInfraBackup({
    required this.schedule,
    required this.retain,
    required this.verifiedRestoreWithin,
  });

  /// A five-field cron line.
  final String schedule;

  final Duration retain;

  /// How old the last verified restore may be before `DV-INFRA-004`.
  ///
  /// The section says "the configured window" without naming a key. The
  /// default is the retention: a restore verified longer ago than that
  /// proved a backup that has since been deleted.
  final Duration verifiedRestoreWithin;
}

/// `database`: access and backups, never the database server itself.
final class DVInfraDatabase {
  const DVInfraDatabase({required this.adapter, this.backup});

  final String adapter;
  final DVInfraBackup? backup;
}

/// One environment under `dartvel.infra`.
final class DVInfraManifest {
  const DVInfraManifest({
    required this.environment,
    required this.adapter,
    required this.hosts,
    this.ssh = const DVInfraSsh(),
    this.tls,
    this.proxy,
    this.services = const DVInfraServices(),
    this.database,
    this.logsShip,
  });

  final String environment;
  final DVInfraAdapterKind adapter;
  final List<String> hosts;
  final DVInfraSsh ssh;
  final DVInfraTls? tls;

  /// The reverse proxy adapter; only `caddy` is read.
  final String? proxy;
  final DVInfraServices services;
  final DVInfraDatabase? database;
  final String? logsShip;

  static final RegExp _hostname = RegExp(
    r'^[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$',
  );
  static final RegExp _name = RegExp(r'^[a-z0-9][a-z0-9_-]{0,62}$');
  static final RegExp _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  /// Reads the `dartvel.infra` map, keyed by environment.
  static Map<String, DVInfraManifest> fromConfig(Object? infra) {
    if (infra == null) return const <String, DVInfraManifest>{};
    final Map<Object?, Object?> envs = _map(infra, 'dartvel.infra');
    final Map<String, DVInfraManifest> out = <String, DVInfraManifest>{};
    for (final MapEntry<Object?, Object?> entry in envs.entries) {
      final Object? key = entry.key;
      if (key is! String || !_name.hasMatch(key)) {
        throw FormatException(
          'dartvel.infra.$key is not an environment name '
          '(lower-case letters, digits, - and _)',
        );
      }
      out[key] = _environment(key, _map(entry.value, 'dartvel.infra.$key'));
    }
    return out;
  }

  static DVInfraManifest _environment(String env, Map<Object?, Object?> map) {
    final String path = 'dartvel.infra.$env';
    _onlyKeys(map, path, const <String>{
      'adapter',
      'hosts',
      'ssh',
      'tls',
      'proxy',
      'services',
      'database',
      'logs',
    });

    final Object? rawAdapter = map['adapter'] ?? 'ssh';
    final DVInfraAdapterKind adapter = DVInfraAdapterKind.values.firstWhere(
      (DVInfraAdapterKind a) => a.configName == rawAdapter,
      orElse: () => throw FormatException(
        '$path.adapter must be one of '
        '${DVInfraAdapterKind.values.map((DVInfraAdapterKind a) => a.configName).join(' | ')}, '
        'got $rawAdapter',
      ),
    );

    final Object? rawHosts = map['hosts'];
    if (rawHosts is! List || rawHosts.isEmpty) {
      throw FormatException('$path.hosts must list at least one host');
    }
    final List<String> hosts = <String>[];
    for (final Object? host in rawHosts) {
      // Hosts reach an ssh command line. Anything but a plain name or address
      // is refused here rather than quoted there: `-oProxyCommand=...` is a
      // perfectly quoted argument that ssh still reads as an option.
      if (host is! String || !_hostname.hasMatch(host)) {
        throw FormatException('$path.hosts: "$host" is not a host name');
      }
      hosts.add(host);
    }

    DVInfraSsh ssh = const DVInfraSsh();
    if (map['ssh'] != null) {
      final Map<Object?, Object?> s = _map(map['ssh'], '$path.ssh');
      _onlyKeys(s, '$path.ssh', const <String>{'user', 'port', 'knownHosts'});
      final Object? user = s['user'] ?? ssh.user;
      if (user is! String || !RegExp(r'^[a-z_][a-z0-9_-]{0,31}$').hasMatch(user)) {
        throw FormatException('$path.ssh.user: "$user" is not a user name');
      }
      final Object? port = s['port'] ?? ssh.port;
      if (port is! int || port < 1 || port > 65535) {
        throw FormatException('$path.ssh.port must be a port number, got $port');
      }
      final Object? known = s['knownHosts'] ?? ssh.knownHosts;
      if (known is! String || known.trim().isEmpty) {
        throw FormatException('$path.ssh.knownHosts must be a path');
      }
      ssh = DVInfraSsh(user: user, port: port, knownHosts: known);
    }

    String? proxy;
    if (map['proxy'] != null) {
      final Map<Object?, Object?> p = _map(map['proxy'], '$path.proxy');
      _onlyKeys(p, '$path.proxy', const <String>{'adapter'});
      if (p['adapter'] != 'caddy') {
        throw FormatException(
          '$path.proxy.adapter must be caddy, got ${p['adapter']}',
        );
      }
      proxy = 'caddy';
    }

    DVInfraTls? tls;
    if (map['tls'] != null) {
      final Map<Object?, Object?> t = _map(map['tls'], '$path.tls');
      _onlyKeys(t, '$path.tls', const <String>{'domains', 'acme'});
      final Object? domains = t['domains'];
      if (domains is! List || domains.isEmpty) {
        throw FormatException('$path.tls.domains must list at least one domain');
      }
      for (final Object? d in domains) {
        if (d is! String || !_hostname.hasMatch(d) || !d.contains('.')) {
          throw FormatException('$path.tls.domains: "$d" is not a domain');
        }
      }
      final Map<Object?, Object?> acme = _map(t['acme'], '$path.tls.acme');
      _onlyKeys(acme, '$path.tls.acme', const <String>{'email'});
      final Object? email = acme['email'];
      if (email is! String || !_email.hasMatch(email)) {
        throw FormatException('$path.tls.acme.email must be an address');
      }
      if (proxy == null) {
        throw FormatException(
          '$path.tls needs $path.proxy: the proxy is what terminates TLS and '
          'renews the certificate, and without one nothing would',
        );
      }
      tls = DVInfraTls(
        domains: List<String>.unmodifiable(domains.cast<String>()),
        acmeEmail: email,
      );
    }

    DVInfraServices services = const DVInfraServices();
    if (map['services'] != null) {
      services = _services(_map(map['services'], '$path.services'), path);
    }

    DVInfraDatabase? database;
    if (map['database'] != null) {
      final Map<Object?, Object?> d = _map(map['database'], '$path.database');
      _onlyKeys(d, '$path.database', const <String>{'adapter', 'backup'});
      if (d['adapter'] != 'postgres') {
        throw FormatException(
          '$path.database.adapter must be postgres, got ${d['adapter']}',
        );
      }
      DVInfraBackup? backup;
      if (d['backup'] != null) {
        final Map<Object?, Object?> b = _map(
          d['backup'],
          '$path.database.backup',
        );
        _onlyKeys(b, '$path.database.backup', const <String>{
          'schedule',
          'retain',
          'verifiedRestoreWithin',
        });
        final Object? schedule = b['schedule'];
        if (schedule is! String) {
          throw FormatException('$path.database.backup.schedule must be a cron line');
        }
        try {
          dvCronToOnCalendar(schedule);
        } on FormatException catch (e) {
          throw FormatException('$path.database.backup.schedule: ${e.message}');
        }
        final Duration retain = _days(b['retain'], '$path.database.backup.retain');
        backup = DVInfraBackup(
          schedule: schedule,
          retain: retain,
          verifiedRestoreWithin: b.containsKey('verifiedRestoreWithin')
              ? _days(
                  b['verifiedRestoreWithin'],
                  '$path.database.backup.verifiedRestoreWithin',
                )
              : retain,
        );
      }
      database = DVInfraDatabase(adapter: 'postgres', backup: backup);
    }

    String? logsShip;
    if (map['logs'] != null) {
      final Map<Object?, Object?> l = _map(map['logs'], '$path.logs');
      _onlyKeys(l, '$path.logs', const <String>{'ship'});
      final Object? ship = l['ship'];
      if (ship is! String || ship.isEmpty) {
        throw FormatException('$path.logs.ship must name a destination');
      }
      logsShip = ship;
    }

    return DVInfraManifest(
      environment: env,
      adapter: adapter,
      hosts: List<String>.unmodifiable(hosts),
      ssh: ssh,
      tls: tls,
      proxy: proxy,
      services: services,
      database: database,
      logsShip: logsShip,
    );
  }

  static DVInfraServices _services(Map<Object?, Object?> s, String env) {
    final String path = '$env.services';
    _onlyKeys(s, path, const <String>{'backend', 'workers', 'cron'});
    int backend = 1;
    if (s['backend'] != null) {
      final Map<Object?, Object?> b = _map(s['backend'], '$path.backend');
      _onlyKeys(b, '$path.backend', const <String>{'instances'});
      if (b.containsKey('instances')) {
        backend = _instances(b['instances'], '$path.backend.instances');
      }
    }
    List<String> queues = const <String>[];
    int workers = 0;
    if (s['workers'] != null) {
      final Map<Object?, Object?> w = _map(s['workers'], '$path.workers');
      _onlyKeys(w, '$path.workers', const <String>{'queues', 'instances'});
      final Object? rawQueues = w['queues'];
      if (rawQueues is! List || rawQueues.isEmpty) {
        throw FormatException('$path.workers.queues must list at least one queue');
      }
      for (final Object? q in rawQueues) {
        if (q is! String || !_name.hasMatch(q)) {
          throw FormatException('$path.workers.queues: "$q" is not a queue name');
        }
      }
      if (rawQueues.toSet().length != rawQueues.length) {
        throw FormatException('$path.workers.queues names a queue twice');
      }
      queues = List<String>.unmodifiable(rawQueues.cast<String>());
      workers = w.containsKey('instances')
          ? _instances(w['instances'], '$path.workers.instances')
          : 1;
    }
    bool? cron;
    if (s['cron'] != null) {
      final Map<Object?, Object?> c = _map(s['cron'], '$path.cron');
      _onlyKeys(c, '$path.cron', const <String>{'enabled'});
      final Object? enabled = c['enabled'];
      if (enabled is! bool) {
        throw FormatException('$path.cron.enabled must be true or false');
      }
      cron = enabled;
    }
    return DVInfraServices(
      backendInstances: backend,
      workerQueues: queues,
      workerInstances: workers,
      cron: cron,
    );
  }

  static int _instances(Object? value, String path) {
    if (value is! int || value < 1 || value > 64) {
      throw FormatException('$path must be a whole number from 1 to 64, got $value');
    }
    return value;
  }

  static Duration _days(Object? value, String path) {
    final Match? m = value is String
        ? RegExp(r'^\s*(\d+)\s*([dh])\s*$').firstMatch(value)
        : null;
    if (m == null) {
      throw FormatException('$path must be days or hours (e.g. 30d), got $value');
    }
    final int n = int.parse(m.group(1)!);
    if (n == 0) throw FormatException('$path must be positive, got $value');
    return m.group(2) == 'h' ? Duration(hours: n) : Duration(days: n);
  }

  static Map<Object?, Object?> _map(Object? value, String path) {
    if (value is Map) return value.cast<Object?, Object?>();
    throw FormatException('$path must be a map, got $value');
  }

  static void _onlyKeys(
    Map<Object?, Object?> map,
    String path,
    Set<String> allowed,
  ) {
    for (final Object? key in map.keys) {
      if (!allowed.contains(key)) {
        throw FormatException(
          '$path.$key is not a setting; expected one of ${allowed.join(', ')}',
        );
      }
    }
  }
}

const List<String> _weekdays = <String>[
  'Sun',
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
];

/// A five-field cron line as a systemd `OnCalendar=` expression.
///
/// Numbers, `*`, lists, ranges and steps. Names and `@daily` are refused
/// rather than guessed at. A line restricting both day of month and day of
/// week is refused too: cron fires when *either* matches and systemd only
/// when *both* do, so the same text would back up on different days.
String dvCronToOnCalendar(String line) {
  final List<String> fields = line.trim().split(RegExp(r'\s+'));
  if (fields.length != 5) {
    throw FormatException('"$line" is not a five-field cron line');
  }
  final _CronField minute = _CronField.parse(fields[0], 0, 59, 'minute');
  final _CronField hour = _CronField.parse(fields[1], 0, 23, 'hour');
  final _CronField dom = _CronField.parse(fields[2], 1, 31, 'day of month');
  final _CronField month = _CronField.parse(fields[3], 1, 12, 'month');
  final _CronField dow = _CronField.parse(fields[4], 0, 7, 'day of week');
  if (!dom.any && !dow.any) {
    throw FormatException(
      '"$line" restricts both day of month and day of week; cron matches '
      'either and a systemd timer would need both, so it is refused rather '
      'than translated into a different schedule',
    );
  }

  final StringBuffer out = StringBuffer();
  if (!dow.any) {
    final List<int> days = <int>{
      for (final int d in dow.values) d == 0 ? 7 : d,
    }.toList()..sort();
    final List<String> parts = <String>[];
    int i = 0;
    while (i < days.length) {
      int j = i;
      while (j + 1 < days.length && days[j + 1] == days[j] + 1) {
        j++;
      }
      String name(int d) => _weekdays[d % 7];
      if (j - i >= 2) {
        parts.add('${name(days[i])}..${name(days[j])}');
      } else {
        for (int k = i; k <= j; k++) {
          parts.add(name(days[k]));
        }
      }
      i = j + 1;
    }
    out.write('${parts.join(',')} ');
  }
  out.write('*-${month.render(1)}-${dom.render(1)} ');
  out.write('${hour.render(0)}:${minute.render(0)}:00');
  return out.toString();
}

final class _CronField {
  _CronField(this.any, this.step, this.values);

  /// `*`.
  final bool any;

  /// `*/n`, kept compact.
  final int? step;
  final List<int> values;

  static _CronField parse(String text, int min, int max, String what) {
    if (text == '*') return _CronField(true, null, const <int>[]);
    final Match? everyN = RegExp(r'^\*/(\d+)$').firstMatch(text);
    if (everyN != null) {
      final int n = int.parse(everyN.group(1)!);
      if (n < 1 || n > max) {
        throw FormatException('$what step "$text" is out of range');
      }
      // Day of week has no compact systemd form; spelt out below.
      if (what == 'day of week') {
        return _CronField(false, null, <int>[
          for (int v = min; v <= 6; v += n) v,
        ]);
      }
      return _CronField(false, n, const <int>[]);
    }
    final Set<int> values = <int>{};
    for (final String part in text.split(',')) {
      final Match? m = RegExp(r'^(\d+)(?:-(\d+))?(?:/(\d+))?$').firstMatch(part);
      if (m == null) {
        throw FormatException('$what "$text" is not numbers, ranges or steps');
      }
      final int from = int.parse(m.group(1)!);
      final int to = m.group(2) == null ? from : int.parse(m.group(2)!);
      final int by = m.group(3) == null ? 1 : int.parse(m.group(3)!);
      if (from < min || to > max || from > to || by < 1) {
        throw FormatException('$what "$part" is outside $min-$max');
      }
      for (int v = from; v <= to; v += by) {
        values.add(v);
      }
    }
    return _CronField(false, null, values.toList()..sort());
  }

  String render(int start) {
    String pad(int v) => v.toString().padLeft(2, '0');
    if (any) return '*';
    if (step != null) return '${pad(start)}/$step';
    return values.map(pad).join(',');
  }
}
